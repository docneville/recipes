-- Migration: "why this matters to our family" field (recipes-b28.7)
-- Distinct from recipes.notes (practical cooking tips/substitutions) -
-- this is the story/sentiment: whose recipe it was, what occasion it's
-- tied to, why it's worth keeping.

ALTER TABLE recipes
  ADD COLUMN significance TEXT;
