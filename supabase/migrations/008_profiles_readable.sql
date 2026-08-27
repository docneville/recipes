-- Migration: let any approved user read any profile (recipes-b28.3)
-- Needed to show "Added by <name>" on a recipe someone else added, now
-- that recipes-b28.2 lets everyone browse everyone's recipes.

-- is_approved() (migration 006) queries profiles internally. It was
-- defined as a plain (non-SECURITY DEFINER) function, which was fine
-- when only used from OTHER tables' policies (recipes, tags) - but using
-- it in profiles' OWN SELECT policy would self-reference: evaluating the
-- policy calls is_approved(), which queries profiles, which re-evaluates
-- the same policy, ad infinitum. Redefining as SECURITY DEFINER (owned
-- by the migration-running role, which owns the table and so bypasses
-- RLS by default) makes the internal lookup skip RLS entirely, breaking
-- the cycle. search_path is pinned per SECURITY DEFINER best practice.
CREATE OR REPLACE FUNCTION is_approved()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND approval_status = 'approved'
  );
$$;

-- id = auth.uid() stays as an explicit alternative (not just is_approved())
-- because a pending/rejected/suspended user still needs to read their OWN
-- row - that's how index.html knows to show the waiting/rejected message
-- in the first place. Without it, an unapproved user's own profile
-- SELECT would return zero rows and the approval-status UI would break.
DROP POLICY "Users can view their own profile" ON profiles;
CREATE POLICY "Own profile or any approved user's profile is readable" ON profiles
  FOR SELECT USING (id = auth.uid() OR is_approved());
