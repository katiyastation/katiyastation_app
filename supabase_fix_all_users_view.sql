-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS - FIX v_all_users VIEW (TYPE-SAFE CAST)
-- Run this in Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- Drop the old function
DROP FUNCTION IF EXISTS public.get_all_users();

-- Create a SECURITY DEFINER function that returns all users safely with correct casts
CREATE OR REPLACE FUNCTION public.get_all_users()
RETURNS TABLE (
  id          UUID,
  full_name   TEXT,
  role        TEXT,
  is_active   BOOLEAN,
  phone       TEXT,
  created_at  TIMESTAMPTZ,
  invited_by  UUID,
  branch_name TEXT,
  branch_id   UUID,
  email       TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  -- Only super_admin can call this
  IF public.get_user_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Access denied: only super_admin can list all users.';
  END IF;

  RETURN QUERY
  SELECT
    up.id,
    up.full_name::TEXT,
    up.role::TEXT,
    up.is_active,
    up.phone::TEXT,
    up.created_at,
    up.invited_by,
    b.name::TEXT   AS branch_name,
    b.id           AS branch_id,
    au.email::TEXT AS email
  FROM public.user_profiles up
  LEFT JOIN public.branches b  ON b.id  = up.branch_id
  LEFT JOIN auth.users      au ON au.id = up.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_all_users() TO authenticated;
