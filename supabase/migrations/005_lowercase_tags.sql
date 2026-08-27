-- Migration: normalize tag names to lowercase so they consolidate
-- recipes-6jh: 'Dinner', 'dinner', 'DINNER' were three separate rows
-- since tags.name matching was case-sensitive everywhere. Merges existing
-- duplicates (re-pointing recipe_tags before dropping the loser), then
-- lowercases everything, then adds a trigger so it can't regress.

-- ============================================
-- Step 1: for each user, merge any tags that collide once lowercased -
-- re-point recipe_tags from every "loser" (kept = the row with the
-- earliest created_at, an arbitrary but stable tie-breaker) onto the
-- "winner", skipping any (recipe_id, tag_id) pair that would violate
-- recipe_tags' primary key because the recipe is already tagged with the
-- winner.
-- ============================================
WITH ranked AS (
  SELECT
    id,
    user_id,
    lower(trim(name)) AS norm_name,
    row_number() OVER (
      PARTITION BY user_id, lower(trim(name))
      ORDER BY created_at ASC
    ) AS rn
  FROM tags
),
winners AS (
  SELECT user_id, norm_name, id AS winner_id
  FROM ranked
  WHERE rn = 1
),
losers AS (
  SELECT r.id AS loser_id, w.winner_id
  FROM ranked r
  JOIN winners w ON w.user_id = r.user_id AND w.norm_name = r.norm_name
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

-- Drop any recipe_tags rows still pointing at a loser (the recipe was
-- already tagged with the winner too, so the re-point above skipped it).
DELETE FROM recipe_tags rt
USING (
  SELECT r.id AS loser_id
  FROM (
    SELECT id, user_id, lower(trim(name)) AS norm_name,
      row_number() OVER (PARTITION BY user_id, lower(trim(name)) ORDER BY created_at ASC) AS rn
    FROM tags
  ) r
  WHERE r.rn > 1
) losers
WHERE rt.tag_id = losers.loser_id;

-- Now the losers are unreferenced - delete them.
DELETE FROM tags t
USING (
  SELECT id, user_id, lower(trim(name)) AS norm_name,
    row_number() OVER (PARTITION BY user_id, lower(trim(name)) ORDER BY created_at ASC) AS rn
  FROM tags
) r
WHERE t.id = r.id AND r.rn > 1;

-- ============================================
-- Step 2: lowercase every surviving tag name.
-- ============================================
UPDATE tags SET name = lower(trim(name)) WHERE name <> lower(trim(name));

-- ============================================
-- Step 3: enforce going forward, at the DB level, so no future code path
-- (client bug, new page, direct API call) can reintroduce mixed casing.
-- ============================================
CREATE OR REPLACE FUNCTION lowercase_tag_name()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.name = lower(trim(NEW.name));
  RETURN NEW;
END;
$$;

CREATE TRIGGER tags_lowercase_name
  BEFORE INSERT OR UPDATE ON tags
  FOR EACH ROW EXECUTE FUNCTION lowercase_tag_name();
