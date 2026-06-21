-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — AUTO-CONFIRMATION TRIGGER & CLEANUP
-- Run this in your Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. CLEAN UP THE BROKEN SANJAY GUPTA USER ──
-- We delete the old record from auth.users. 
-- Due to ON DELETE CASCADE, the public.user_profiles row will be automatically deleted.
DELETE FROM auth.users WHERE email = 'sanjaygupta@gmail.com';


-- ── 2. CREATE AUTO-CONFIRMATION TRIGGER ──
-- This trigger runs BEFORE a user is inserted into auth.users.
-- It automatically confirms the email, which ensures GoTrue makes the user active immediately.
CREATE OR REPLACE FUNCTION public.auto_confirm_new_user()
RETURNS TRIGGER AS $$
BEGIN
  NEW.email_confirmed_at := COALESCE(NEW.email_confirmed_at, NOW());
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Drop trigger if already exists, then create it
DROP TRIGGER IF EXISTS on_auth_user_created_before ON auth.users;
CREATE TRIGGER on_auth_user_created_before
  BEFORE INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.auto_confirm_new_user();


-- ── 3. ENSURE ADMIN PROFILE SETUP FUNCTION IS READY ──
-- This function is called by the Flutter app after signing up the user.
-- It sets up the role, branch, full_name, and logs it.
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

  INSERT INTO public.user_profiles (id, full_name, role, branch_id, invited_by, is_active, created_at, updated_at)
  VALUES (p_user_id, p_full_name, p_role, p_branch_id, p_invited_by, true, NOW(), NOW())
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

GRANT EXECUTE ON FUNCTION public.admin_setup_user_profile TO authenticated;

-- ── 4. SHOW CURRENT USERS STATUS ──
SELECT 
  email,
  created_at
FROM auth.users;
