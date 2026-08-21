-- Migration: Core schema (recipes, tags, recipe_tags)
-- Personal recipe box: everything scoped directly to user_id, no
-- shared-household layer like Houstory's property_members - this is
-- single-user for now.

-- ============================================
-- recipes: one row per recipe
-- ingredients/instructions are JSONB arrays (structured lists) rather
-- than free text, so the UI can render and edit them item-by-item:
--   ingredients: [{ "quantity": "2", "unit": "cups", "name": "flour", "notes": "" }, ...]
--   instructions: ["Preheat oven to 350F.", "Mix dry ingredients.", ...]
-- ============================================
CREATE TABLE recipes (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title          TEXT NOT NULL,
  description    TEXT,
  source_url     TEXT,
  source_name    TEXT,
  prep_minutes   INTEGER,
  cook_minutes   INTEGER,
  servings       TEXT,
  ingredients    JSONB NOT NULL DEFAULT '[]'::jsonb,
  instructions   JSONB NOT NULL DEFAULT '[]'::jsonb,
  notes          TEXT,
  photo_path     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE recipes ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_recipes_user ON recipes(user_id);

CREATE POLICY "Users can view their own recipes" ON recipes
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can create their own recipes" ON recipes
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own recipes" ON recipes
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own recipes" ON recipes
  FOR DELETE USING (user_id = auth.uid());

-- ============================================
-- tags: user-scoped, deduplicated by lowercase name
-- ============================================
CREATE TABLE tags (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, name)
);

ALTER TABLE tags ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_tags_user ON tags(user_id);

CREATE POLICY "Users can view their own tags" ON tags
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can create their own tags" ON tags
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own tags" ON tags
  FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY "Users can delete their own tags" ON tags
  FOR DELETE USING (user_id = auth.uid());

-- ============================================
-- recipe_tags: many-to-many join
-- ============================================
CREATE TABLE recipe_tags (
  recipe_id UUID NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
  tag_id    UUID NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
  PRIMARY KEY (recipe_id, tag_id)
);

ALTER TABLE recipe_tags ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_recipe_tags_tag ON recipe_tags(tag_id);

-- recipe_tags policies reference only recipes/tags (both already scoped to
-- auth.uid() above), never recipe_tags itself, to avoid RLS self-recursion.
CREATE POLICY "Users can view recipe_tags for their own recipes" ON recipe_tags
  FOR SELECT USING (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can tag their own recipes" ON recipe_tags
  FOR INSERT WITH CHECK (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND tag_id IN (SELECT id FROM tags WHERE user_id = auth.uid())
  );

CREATE POLICY "Users can untag their own recipes" ON recipe_tags
  FOR DELETE USING (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
  );

-- ============================================
-- Keep updated_at current
-- ============================================
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

CREATE TRIGGER recipes_touch_updated_at
  BEFORE UPDATE ON recipes
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
