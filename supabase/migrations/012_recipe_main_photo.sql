-- Migration: main photo selection (recipes-ten)
-- A single FK pointer rather than a recipe_photos.is_main boolean - no
-- uniqueness constraint/trigger needed to enforce "only one main photo
-- per recipe", and ON DELETE SET NULL cleanly falls back to "no main
-- photo set" (thumbnail features should fall back to first-uploaded) if
-- the designated photo is later deleted.

ALTER TABLE recipes
  ADD COLUMN main_photo_id UUID REFERENCES recipe_photos(id) ON DELETE SET NULL;

-- No new RLS policy needed - setting this is just a normal recipes
-- UPDATE, already scoped to the owner + is_approved() (migration 006),
-- and recipes' UPDATE grant isn't column-restricted the way profiles' is.
