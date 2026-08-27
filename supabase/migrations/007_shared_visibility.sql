-- Migration: My Recipes vs All Recipes shared family visibility (recipes-b28.2)
-- Opens SELECT on recipes/tags/recipe_tags and recipe-photos storage
-- reads to any approved user, not just the owner - safe now that
-- recipes-b28.1's approval gate exists. Writes (INSERT/UPDATE/DELETE on
-- recipes, and photo INSERT/DELETE) stay owner-scoped - you can browse
-- everyone's recipes but only edit/delete your own.

-- ============================================
-- recipes: open SELECT to any approved user.
-- ============================================
DROP POLICY "Users can view their own recipes" ON recipes;
CREATE POLICY "Approved users can view all recipes" ON recipes
  FOR SELECT USING (is_approved());

-- ============================================
-- tags: resolved the open design question from when this issue was
-- filed - tags become a single shared vocabulary across the family
-- rather than per-user silos, since "All Recipes" browsing a tag filter
-- built only from the viewer's own tags would be incomplete, and two
-- separate 'dinner' rows (one per user) showing as two chips would be
-- confusing. Merge any name collisions across users first (same
-- re-point-then-delete pattern as migration 005, but keyed by name
-- alone now instead of per-user), then drop the per-user uniqueness.
-- ============================================
WITH ranked AS (
  SELECT id, name, row_number() OVER (PARTITION BY name ORDER BY created_at ASC) AS rn
  FROM tags
),
winners AS (
  SELECT name, id AS winner_id FROM ranked WHERE rn = 1
),
losers AS (
  SELECT r.id AS loser_id, w.winner_id
  FROM ranked r JOIN winners w ON w.name = r.name
  WHERE r.rn > 1
)
UPDATE recipe_tags rt
SET tag_id = l.winner_id
FROM losers l
WHERE rt.tag_id = l.loser_id
  AND NOT EXISTS (
    SELECT 1 FROM recipe_tags rt2
    WHERE rt2.recipe_id = rt.recipe_id AND rt2.tag_id = l.winner_id
  );

DELETE FROM recipe_tags rt
USING (
  SELECT id AS loser_id
  FROM (SELECT id, name, row_number() OVER (PARTITION BY name ORDER BY created_at ASC) AS rn FROM tags) r
  WHERE r.rn > 1
) losers
WHERE rt.tag_id = losers.loser_id;

DELETE FROM tags t
USING (
  SELECT id, name, row_number() OVER (PARTITION BY name ORDER BY created_at ASC) AS rn FROM tags
) r
WHERE t.id = r.id AND r.rn > 1;

-- Drop whatever the old UNIQUE(user_id, name) constraint is actually
-- named (looked up rather than hardcoded, since Postgres auto-generates
-- constraint names and this is safer than guessing).
DO $$
DECLARE
  con_name TEXT;
BEGIN
  SELECT conname INTO con_name
  FROM pg_constraint
  WHERE conrelid = 'tags'::regclass AND contype = 'u'
  LIMIT 1;
  IF con_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE tags DROP CONSTRAINT %I', con_name);
  END IF;
END $$;

ALTER TABLE tags ADD CONSTRAINT tags_name_key UNIQUE (name);

-- tags.user_id stays (renamed in spirit to "who coined this tag", not
-- "who owns it") but is no longer used for matching, RLS scoping, or
-- uniqueness.
DROP POLICY "Users can view their own tags" ON tags;
CREATE POLICY "Approved users can view all tags" ON tags
  FOR SELECT USING (is_approved());

DROP POLICY "Users can create their own tags" ON tags;
CREATE POLICY "Approved users can create tags" ON tags
  FOR INSERT WITH CHECK (user_id = auth.uid() AND is_approved());

-- No UPDATE/DELETE policy for the authenticated role - nothing in the
-- app renames or deletes a shared tag today (add-recipe.html only
-- inserts new ones and manages recipe_tags associations), and "can any
-- family member delete a tag everyone uses" isn't a question worth
-- deciding by omission. Only service_role can, for now.
DROP POLICY "Users can update their own tags" ON tags;
DROP POLICY "Users can delete their own tags" ON tags;

-- ============================================
-- recipe_tags: SELECT opens the same way; INSERT no longer checks tag
-- ownership (tags aren't owned anymore) but still requires the recipe
-- itself to be yours.
-- ============================================
DROP POLICY "Users can view recipe_tags for their own recipes" ON recipe_tags;
CREATE POLICY "Approved users can view all recipe_tags" ON recipe_tags
  FOR SELECT USING (is_approved());

DROP POLICY "Users can tag their own recipes" ON recipe_tags;
CREATE POLICY "Users can tag their own recipes" ON recipe_tags
  FOR INSERT WITH CHECK (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND is_approved()
  );

-- ============================================
-- recipe-photos storage: open reads to any approved user (their source
-- photos need to be viewable on someone else's screen once recipes are
-- shared). Uploads/deletes stay folder-scoped to the owner (unchanged
-- from migration 006).
-- ============================================
DROP POLICY "Users can read their own recipe photos" ON storage.objects;
CREATE POLICY "Approved users can read all recipe photos" ON storage.objects
  FOR SELECT USING (bucket_id = 'recipe-photos' AND is_approved());
