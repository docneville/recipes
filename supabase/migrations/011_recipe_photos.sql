-- Migration: finished-dish photos, multiple per recipe with descriptions
-- (recipes-022.3). Design note: this issue was originally scoped before
-- recipes-b28.2 (shared My/All Recipes visibility) shipped, so unlike
-- its own older notes, SELECT here is approval-gated like every other
-- shared table (recipes, tags, recipe_tags), not owner-scoped - anyone
-- who can see a recipe can see its finished-dish photos too. Only the
-- recipe's owner can add/remove/edit them.

CREATE TABLE recipe_photos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recipe_id    UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  storage_path TEXT NOT NULL,
  description  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE recipe_photos ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_recipe_photos_recipe ON recipe_photos(recipe_id);

CREATE POLICY "Approved users can view all recipe photos" ON recipe_photos
  FOR SELECT USING (is_approved());

CREATE POLICY "Users can add photos to their own recipes" ON recipe_photos
  FOR INSERT WITH CHECK (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND is_approved()
  );

CREATE POLICY "Users can edit photo descriptions on their own recipes" ON recipe_photos
  FOR UPDATE USING (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND is_approved()
  );

CREATE POLICY "Users can delete photos from their own recipes" ON recipe_photos
  FOR DELETE USING (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND is_approved()
  );
