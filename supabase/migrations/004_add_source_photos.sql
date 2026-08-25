-- Migration: source_photo_paths on recipes
-- recipes-022.2 (AI photo-to-recipe import): the original photo(s) a
-- recipe was extracted from (a cookbook page, a screenshot series) are
-- kept and attached to the saved recipe, distinct from photo_path (a
-- future "finished dish" photo, recipes-022.3). Storage paths live under
-- the same recipe-photos bucket, {user_id}/imports/... prefix - already
-- covered by migration 002's {user_id} folder-gated RLS policies, no new
-- bucket or policy needed.

ALTER TABLE recipes
  ADD COLUMN source_photo_paths JSONB NOT NULL DEFAULT '[]'::jsonb;
