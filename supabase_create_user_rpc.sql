-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS - SECURE SERVER-SIDE USER CREATION RPC
-- Run this in your Supabase SQL editor.
-- ═══════════════════════════════════════════════════════════════

-- ── Drop old function if exists ─────────────────────────────────
DROP FUNCTION IF EXISTS public.admin_create_auth_user(TEXT, TEXT, TEXT, TEXT, UUID, UUID);

-- ── Main user provisioning function ────────────────────────────
-- NOTE: search_path includes 'extensions' so pgcrypto functions
-- (crypt, gen_salt) resolve correctly in Supabase.
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
  v_user_id     UUID;
  v_now         TIMESTAMPTZ := NOW();
BEGIN
  -- 1. Guard: only super_admin can call this
  IF public.get_user_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Only super admins can create users.';
  END IF;

  -- 2. Check email not already taken
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = lower(p_email)) THEN
    RAISE EXCEPTION 'A user with this email already exists.';
  END IF;

  -- 3. Generate a new UUID for the user
  v_user_id := gen_random_uuid();

  -- 4. Insert into auth.users
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
    crypt(p_password, gen_salt('bf')),
    v_now,                -- auto-confirm email
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name, 'role', p_role),
    v_now,
    v_now,
    '',
    '',
    false
  );

  -- 5. Insert into auth.identities (REQUIRED by Supabase GoTrue for login to work!)
  INSERT INTO auth.identities (
    id,                  -- UUID: primary key
    provider_id,         -- TEXT: provider-specific ID (user's UUID as text)
    user_id,             -- UUID: references auth.users
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  ) VALUES (
    v_user_id,            -- id (UUID)
    v_user_id::text,      -- provider_id (TEXT)
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

  -- 6. Upsert user profile (handle_new_user trigger may have already inserted a row)
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

  -- 7. Audit log
  INSERT INTO public.user_access_logs (performed_by, target_user, action, notes)
  VALUES (
    COALESCE(p_invited_by, auth.uid()),
    v_user_id,
    'created',
    'email: ' || lower(p_email) || ', role: ' || p_role
  );

  RETURN json_build_object('success', true, 'user_id', v_user_id, 'email', p_email);

EXCEPTION
  WHEN OTHERS THEN RAISE;
END;
$$;

-- Grant execute to authenticated role (the function itself enforces super_admin guard)
GRANT EXECUTE ON FUNCTION public.admin_create_auth_user(TEXT, TEXT, TEXT, TEXT, UUID, UUID)
  TO authenticated;

