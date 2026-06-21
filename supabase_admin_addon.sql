-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — SUPER ADMIN USER MANAGEMENT SQL ADDITIONS
-- Run this AFTER supabase_schema.sql has already been applied.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. ADD invited_by COLUMN TO user_profiles ──────────────────
ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS invited_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;

-- ── 2. USER ACCESS LOG TABLE ────────────────────────────────────
-- Tracks every time super_admin creates, blocks, or modifies a user account.
CREATE TABLE IF NOT EXISTS public.user_access_logs (
    id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    performed_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    target_user  UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    action       TEXT NOT NULL CHECK (action IN ('created', 'blocked', 'unblocked', 'role_changed', 'branch_changed', 'deleted')),
    notes        TEXT,
    created_at   TIMESTAMPTZ DEFAULT NOW()
);

-- ── 3. ADMIN RPC: Create User Profile after Auth signup ─────────
-- Called by the Flutter app after using the Admin API to create the auth user.
-- This sets the role, branch, full_name, and invited_by fields atomically.
CREATE OR REPLACE FUNCTION public.admin_setup_user_profile(
    p_user_id    UUID,
    p_full_name  TEXT,
    p_role       TEXT,
    p_branch_id  UUID,
    p_invited_by UUID
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only super_admin can call this
  IF (SELECT role FROM public.user_profiles WHERE id = auth.uid()) != 'super_admin' THEN
    RAISE EXCEPTION 'Access denied: only super_admin can provision accounts';
  END IF;

  INSERT INTO public.user_profiles (id, full_name, role, branch_id, invited_by, is_active, created_at)
  VALUES (p_user_id, p_full_name, p_role, p_branch_id, p_invited_by, true, NOW())
  ON CONFLICT (id) DO UPDATE
    SET full_name  = EXCLUDED.full_name,
        role       = EXCLUDED.role,
        branch_id  = EXCLUDED.branch_id,
        invited_by = EXCLUDED.invited_by,
        updated_at = NOW();

  -- Log the creation
  INSERT INTO public.user_access_logs (performed_by, target_user, action, notes)
  VALUES (p_invited_by, p_user_id, 'created', 'Account provisioned by super_admin');
END;
$$;

-- ── 4. ADMIN RPC: Block or Unblock a User ──────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_user_active(
    p_target_user_id UUID,
    p_is_active      BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_action TEXT;
BEGIN
  -- Only super_admin can call this
  IF (SELECT role FROM public.user_profiles WHERE id = auth.uid()) != 'super_admin' THEN
    RAISE EXCEPTION 'Access denied: only super_admin can block/unblock accounts';
  END IF;

  UPDATE public.user_profiles
    SET is_active  = p_is_active,
        updated_at = NOW()
  WHERE id = p_target_user_id;

  v_action := CASE WHEN p_is_active THEN 'unblocked' ELSE 'blocked' END;

  INSERT INTO public.user_access_logs (performed_by, target_user, action)
  VALUES (auth.uid(), p_target_user_id, v_action);
END;
$$;

-- ── 5. ADMIN RPC: Change a User's Role or Branch ───────────────
CREATE OR REPLACE FUNCTION public.admin_update_user(
    p_target_user_id UUID,
    p_role           TEXT DEFAULT NULL,
    p_branch_id      UUID DEFAULT NULL,
    p_full_name      TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF (SELECT role FROM public.user_profiles WHERE id = auth.uid()) != 'super_admin' THEN
    RAISE EXCEPTION 'Access denied';
  END IF;

  UPDATE public.user_profiles
    SET role       = COALESCE(p_role, role),
        branch_id  = COALESCE(p_branch_id, branch_id),
        full_name  = COALESCE(p_full_name, full_name),
        updated_at = NOW()
  WHERE id = p_target_user_id;

  INSERT INTO public.user_access_logs (performed_by, target_user, action, notes)
  VALUES (auth.uid(), p_target_user_id, 'role_changed',
          'role=' || COALESCE(p_role, 'unchanged'));
END;
$$;

-- ── 6. RLS on user_access_logs ─────────────────────────────────
ALTER TABLE public.user_access_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Only super_admin can view access logs"
ON public.user_access_logs FOR SELECT
TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin'
);

-- ── 7. TIGHTEN user_profiles RLS ───────────────────────────────
-- Drop the wide-open read policy and replace with a scoped one.
DROP POLICY IF EXISTS "Allow authenticated users to read profiles" ON public.user_profiles;

CREATE POLICY "Users can read their own profile"
ON public.user_profiles FOR SELECT
TO authenticated
USING (
  id = auth.uid()
  OR (SELECT role FROM public.user_profiles WHERE id = auth.uid()) IN ('super_admin', 'branch_manager')
);

-- Only super_admin can INSERT new profiles (regular signup handled by trigger)
CREATE POLICY "Only super_admin can insert profiles"
ON public.user_profiles FOR INSERT
TO authenticated
WITH CHECK (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin'
);

-- Only super_admin or the user themselves can update
DROP POLICY IF EXISTS "Allow super admins or own profile modification" ON public.user_profiles;
CREATE POLICY "Super admin or self update"
ON public.user_profiles FOR UPDATE
TO authenticated
USING (
  id = auth.uid()
  OR (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin'
);

-- Only super_admin can delete profiles
CREATE POLICY "Only super_admin can delete profiles"
ON public.user_profiles FOR DELETE
TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin'
);

-- ── 8. GRANT EXECUTE on RPC functions ──────────────────────────
GRANT EXECUTE ON FUNCTION public.admin_setup_user_profile TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_user_active TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_user TO authenticated;

-- ── 9. HELPER VIEW: Super admin sees ALL users with branch name ─
CREATE OR REPLACE VIEW public.v_all_users AS
SELECT
  up.id,
  up.full_name,
  up.role,
  up.is_active,
  up.phone,
  up.created_at,
  up.invited_by,
  b.name  AS branch_name,
  b.id    AS branch_id,
  au.email
FROM public.user_profiles up
LEFT JOIN public.branches b ON b.id = up.branch_id
LEFT JOIN auth.users      au ON au.id = up.id;

-- Grant view access to authenticated (RLS on user_profiles filters it already)
GRANT SELECT ON public.v_all_users TO authenticated;
