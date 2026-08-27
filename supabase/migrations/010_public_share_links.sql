-- Migration: public share links, no account needed (recipes-b28.4)
--
-- SECURITY NOTE: the original design for this (see beads recipes-b28.4)
-- proposed an anon RLS policy of USING (share_token IS NOT NULL) on
-- recipes directly. That's unsafe once every recipe has a non-null
-- token: RLS policies are a per-row check independent of the client's
-- own WHERE clause, so an anon client could run an UNFILTERED
-- `SELECT * FROM recipes` and get every recipe back, not just the one
-- row matching whatever token they were actually given - anon has no
-- way to be restricted to "only the row you already know the token
-- for" via a plain table policy. Using a SECURITY DEFINER function
-- instead: it takes the token as an explicit argument, does the
-- filtering itself before RLS even enters the picture (it bypasses RLS
-- internally, same is_approved() pattern as migration 008), and is the
-- ONLY way anon can reach recipe data - there is no direct anon SELECT
-- grant/policy on recipes or profiles.

ALTER TABLE recipes
  ADD COLUMN share_token UUID NOT NULL UNIQUE DEFAULT gen_random_uuid();

CREATE OR REPLACE FUNCTION get_shared_recipe(p_token UUID)
RETURNS TABLE (
  title           TEXT,
  description     TEXT,
  significance    TEXT,
  prep_minutes    INTEGER,
  cook_minutes    INTEGER,
  servings        TEXT,
  ingredients     JSONB,
  instructions    JSONB,
  notes           TEXT,
  source_name     TEXT,
  source_url      TEXT,
  author_first_name TEXT,
  author_last_name  TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT
    r.title, r.description, r.significance,
    r.prep_minutes, r.cook_minutes, r.servings,
    r.ingredients, r.instructions, r.notes,
    r.source_name, r.source_url,
    p.first_name, p.last_name
  FROM recipes r
  LEFT JOIN profiles p ON p.id = r.user_id
  WHERE r.share_token = p_token;
$$;

-- anon has no other way to reach recipes/profiles data - this function
-- is the sole, narrow door, scoped to exactly one row per call.
GRANT EXECUTE ON FUNCTION get_shared_recipe(UUID) TO anon;
