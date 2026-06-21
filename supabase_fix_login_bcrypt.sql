-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — FIX: Branch Manager / Cashier / Waiter Login
-- 
-- ROOT CAUSE:
--   The original admin_create_auth_user RPC used:
--     crypt(p_password, gen_salt('bf'))
--   pgcrypto's gen_salt('bf') defaults to cost factor 6 → generates $2a$06$...
--   But Supabase GoTrue authenticates with bcrypt cost factor 10 → expects $2a$10$...
--   This hash mismatch causes "Invalid login credentials" for ALL non-super-admin users.
--
-- ALSO FIXED:
--   auth.identities primary key `id` must be a NEW uuid (not the user_id) on 
--   some Supabase versions. Using gen_random_uuid() for safety.
--
-- HOW TO APPLY:
--   Run this entire script in your Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- Drop the broken function
DROP FUNCTION IF EXISTS public.admin_create_auth_user(TEXT, TEXT, TEXT, TEXT, UUID, UUID);

-- Re-create with correct bcrypt cost = 10
CREATE OR REPLACE FUNCTION public.admin_create_auth_user(
  p_email       TEXT,
  p_password    TEXT,
  p_full_name   TEXT,
  p_role        TEXT,
  p_branch_id   UUID DEFAULT NULL,
  p_invited_by  UUID DEFAULT NULL
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, auth, public
AS $$
DECLARE
  v_user_id       UUID;
  v_identity_id   UUID;
  v_now           TIMESTAMPTZ := NOW();
  v_encrypted_pw  TEXT;
BEGIN
  -- 1. Guard: only super_admin can call this
  IF public.get_user_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Only super admins can create users.';
  END IF;

  -- 2. Check email not already taken
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = lower(p_email)) THEN
    RAISE EXCEPTION 'A user with this email already exists.';
  END IF;

  -- 3. Generate UUIDs
  v_user_id     := gen_random_uuid();
  v_identity_id := gen_random_uuid();

  -- 4. Hash password with bcrypt cost=10 (matching GoTrue's expected format)
  --    gen_salt('bf', 10) produces $2a$10$... which GoTrue can verify correctly.
  v_encrypted_pw := crypt(p_password, gen_salt('bf', 10));

  -- 5. Insert into auth.users (email auto-confirmed so they can log in immediately)
  INSERT INTO auth.users (
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token,
    is_sso_user
  ) VALUES (
    v_user_id,
    'authenticated',
    'authenticated',
    lower(p_email),
    v_encrypted_pw,
    v_now,                -- auto-confirm: user can log in immediately
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name, 'role', p_role),
    v_now,
    v_now,
    '',
    '',
    false
  );

  -- 6. Insert into auth.identities (required by GoTrue for email/password login)
  --    Use a separate UUID for the identity `id` to avoid PK conflicts.
  INSERT INTO auth.identities (
    id,
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    v_identity_id,          -- separate UUID for identity PK
    v_user_id::text,        -- provider_id: the user's UUID as text (GoTrue standard)
    v_user_id,
    jsonb_build_object(
      'sub',   v_user_id::text,
      'email', lower(p_email)
    ),
    'email',
    v_now,
    v_now,
    v_now
  );

  -- 7. Upsert user profile
  --    (the on_auth_user_created trigger may have already inserted a row with role='waiter')
  --    We upsert to ensure the correct role, branch, and full_name are set.
  INSERT INTO public.user_profiles (
    id, full_name, role, branch_id, is_active, created_at, updated_at
  ) VALUES (
    v_user_id, p_full_name, p_role, p_branch_id, true, v_now, v_now
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name  = EXCLUDED.full_name,
        role       = EXCLUDED.role,
        branch_id  = EXCLUDED.branch_id,
        is_active  = true,
        updated_at = v_now;

  -- 8. Audit log
  INSERT INTO public.user_access_logs (performed_by, target_user, action, notes)
  VALUES (
    COALESCE(p_invited_by, auth.uid()),
    v_user_id,
    'created',
    'email: ' || lower(p_email) || ', role: ' || p_role
  );

  RETURN json_build_object(
    'success', true,
    'user_id', v_user_id,
    'email',   lower(p_email),
    'role',    p_role
  );

EXCEPTION
  WHEN OTHERS THEN RAISE;
END;
$$;

-- Grant execute permission to authenticated role
-- (the function's own guard ensures only super_admin can actually use it)
GRANT EXECUTE ON FUNCTION public.admin_create_auth_user(TEXT, TEXT, TEXT, TEXT, UUID, UUID)
  TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- OPTIONAL: Fix existing broken users' passwords
-- If you already created branch_manager / cashier / waiter users 
-- with the old broken function, their passwords are stored with 
-- cost=6 and GoTrue cannot verify them.
--
-- OPTION A: Reset password manually via Supabase Dashboard 
--   → Authentication → Users → "Send password reset email" or 
--   → "Update password" field
--
-- OPTION B: Run the helper below to reset a specific user's password:
-- ═══════════════════════════════════════════════════════════════

-- Helper: reset a user's password with correct bcrypt cost=10
-- Usage: SELECT public.admin_reset_user_password('user-uuid-here', 'NewPassword123');
CREATE OR REPLACE FUNCTION public.admin_reset_user_password(
  p_user_id  UUID,
  p_password TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = extensions, auth, public
AS $$
BEGIN
  IF public.get_user_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Only super admins can reset passwords.';
  END IF;

  UPDATE auth.users
    SET encrypted_password = crypt(p_password, gen_salt('bf', 10)),
        updated_at         = NOW()
  WHERE id = p_user_id;

  INSERT INTO public.user_access_logs (performed_by, target_user, action, notes)
  VALUES (auth.uid(), p_user_id, 'role_changed', 'Password reset by super_admin');
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reset_user_password(UUID, TEXT) TO authenticated;
