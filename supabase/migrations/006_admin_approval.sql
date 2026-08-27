-- Migration: admin approval gate for new signups (recipes-b28.1)
-- Mirrors Five Wonders' profiles.approval_status/is_admin pattern, but
-- enforced in RLS here (not Edge Functions - Recipes has none; the
-- client talks to tables directly) so it can't be bypassed by a future
-- page that forgets to check it.

ALTER TABLE profiles
  ADD COLUMN approval_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (approval_status IN ('pending', 'approved', 'rejected', 'suspended')),
  ADD COLUMN is_admin BOOLEAN NOT NULL DEFAULT false;

-- ============================================
-- Close a privilege-escalation gap: the existing "Users can update their
-- own profile" RLS policy (migration 003) only restricts WHICH ROW a
-- user can touch, not which columns - as written, any signed-in user
-- could self-approve or self-grant admin via a direct client call
-- (sb.from('profiles').update({approval_status: 'approved'})), bypassing
-- the whole point of this feature. Column-level GRANTs close this at the
-- privilege level, independent of (and more reliable than) RLS's row
-- filtering: the authenticated role simply cannot reference
-- approval_status or is_admin in an INSERT/UPDATE statement at all, no
-- matter what a client sends. Only service_role (used by admin
-- approve/reject, whether via dashboard or a future admin UI) bypasses
-- this and can set them.
-- ============================================
REVOKE INSERT, UPDATE ON profiles FROM authenticated;
GRANT INSERT (id, first_name, last_name, avatar_url) ON profiles TO authenticated;
GRANT UPDATE (first_name, last_name, avatar_url) ON profiles TO authenticated;

-- ============================================
-- Helper for gating writes elsewhere. Not SECURITY DEFINER - runs as the
-- querying role, which already has SELECT on its own profile row via the
-- existing "Users can view their own profile" policy, so this doesn't
-- need elevated privileges to work.
-- ============================================
CREATE OR REPLACE FUNCTION is_approved()
RETURNS BOOLEAN LANGUAGE sql STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND approval_status = 'approved'
  );
$$;

-- ============================================
-- Gate writes on recipes/tags/recipe_tags. SELECT policies are untouched
-- on purpose - they're still scoped to user_id = auth.uid() only (no
-- shared visibility yet, that's recipes-b28.2), so an unapproved user
-- can't see anyone else's data by reading their own empty list; the real
-- risk this closes is writes.
-- ============================================
DROP POLICY "Users can create their own recipes" ON recipes;
CREATE POLICY "Users can create their own recipes" ON recipes
  FOR INSERT WITH CHECK (user_id = auth.uid() AND is_approved());

DROP POLICY "Users can update their own recipes" ON recipes;
CREATE POLICY "Users can update their own recipes" ON recipes
  FOR UPDATE USING (user_id = auth.uid() AND is_approved());

DROP POLICY "Users can delete their own recipes" ON recipes;
CREATE POLICY "Users can delete their own recipes" ON recipes
  FOR DELETE USING (user_id = auth.uid() AND is_approved());

DROP POLICY "Users can create their own tags" ON tags;
CREATE POLICY "Users can create their own tags" ON tags
  FOR INSERT WITH CHECK (user_id = auth.uid() AND is_approved());

DROP POLICY "Users can update their own tags" ON tags;
CREATE POLICY "Users can update their own tags" ON tags
  FOR UPDATE USING (user_id = auth.uid() AND is_approved());

DROP POLICY "Users can delete their own tags" ON tags;
CREATE POLICY "Users can delete their own tags" ON tags
  FOR DELETE USING (user_id = auth.uid() AND is_approved());

DROP POLICY "Users can tag their own recipes" ON recipe_tags;
CREATE POLICY "Users can tag their own recipes" ON recipe_tags
  FOR INSERT WITH CHECK (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND tag_id IN (SELECT id FROM tags WHERE user_id = auth.uid())
    AND is_approved()
  );

DROP POLICY "Users can untag their own recipes" ON recipe_tags;
CREATE POLICY "Users can untag their own recipes" ON recipe_tags
  FOR DELETE USING (
    recipe_id IN (SELECT id FROM recipes WHERE user_id = auth.uid())
    AND is_approved()
  );

-- ============================================
-- Same gate on the recipe-photos storage bucket - uploads and deletes
-- require approval, reads don't (an unapproved user's own
-- already-uploaded photos, if any, stay visible to them - consistent
-- with SELECT above staying ungated).
-- ============================================
DROP POLICY "Users can upload their own recipe photos" ON storage.objects;
CREATE POLICY "Users can upload their own recipe photos" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'recipe-photos'
    AND (storage.foldername(name))[1]::uuid = auth.uid()
    AND is_approved()
  );

DROP POLICY "Users can delete their own recipe photos" ON storage.objects;
CREATE POLICY "Users can delete their own recipe photos" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'recipe-photos'
    AND (storage.foldername(name))[1]::uuid = auth.uid()
    AND is_approved()
  );
