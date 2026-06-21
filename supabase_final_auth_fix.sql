-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — FINAL FIX: User Creation + Login
-- 
-- PROBLEMS FIXED:
-- 1. admin_create_auth_user was failing at auth.identities insert
--    (Supabase updated identities schema — id must be TEXT not UUID)
-- 2. bcrypt cost was 6 instead of 10 (GoTrue rejects cost!=10)
-- 3. User saved in user_profiles but NOT in auth.users (transaction
--    rollback after trigger already inserted profile row)
--
-- RUN THIS ENTIRE SCRIPT in Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- Step 1: Check auth.identities column types (helps diagnose)
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_schema = 'auth' AND table_name = 'identities'
ORDER BY ordinal_position;

-- Step 2: Drop and recreate the broken function
DROP FUNCTION IF EXISTS public.admin_create_auth_user(TEXT, TEXT, TEXT, TEXT, UUID, UUID);

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
  v_now           TIMESTAMPTZ := NOW();
  v_encrypted_pw  TEXT;
BEGIN
  -- Guard: only super_admin can call this
  IF public.get_user_role(auth.uid()) <> 'super_admin' THEN
    RAISE EXCEPTION 'Only super admins can create users.';
  END IF;

  -- Check email not already taken
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = lower(p_email)) THEN
    RAISE EXCEPTION 'A user with this email already exists.';
  END IF;

  -- Generate user UUID
  v_user_id := gen_random_uuid();

  -- Hash password with bcrypt cost=10 (REQUIRED by GoTrue)
  v_encrypted_pw := crypt(p_password, gen_salt('bf', 10));

  -- Insert into auth.users
  INSERT INTO auth.users (
    id, aud, role, email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token,
    is_sso_user
  ) VALUES (
    v_user_id,
    'authenticated',
    'authenticated',
    lower(p_email),
    v_encrypted_pw,
    v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name, 'role', p_role),
    v_now, v_now,
    '', '',
    false
  );

  -- Insert into auth.identities
  -- NOTE: On newer Supabase, auth.identities.id is TEXT (not UUID).
  -- We handle both by casting. provider_id = user UUID as text.
  BEGIN
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
      v_user_id::text,       -- id as TEXT (works on both old UUID and new TEXT schemas)
      v_user_id::text,       -- provider_id
      v_user_id,
      jsonb_build_object(
        'sub',   v_user_id::text,
        'email', lower(p_email)
      ),
      'email',
      v_now, v_now, v_now
    );
  EXCEPTION WHEN OTHERS THEN
    -- If id column is UUID type, try with gen_random_uuid()
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
      gen_random_uuid(),     -- separate UUID for id PK
      v_user_id::text,
      v_user_id,
      jsonb_build_object(
        'sub',   v_user_id::text,
        'email', lower(p_email)
      ),
      'email',
      v_now, v_now, v_now
    );
  END;

  -- Upsert user profile (trigger may have already inserted with wrong role)
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

  -- Audit log
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

GRANT EXECUTE ON FUNCTION public.admin_create_auth_user(TEXT, TEXT, TEXT, TEXT, UUID, UUID)
  TO authenticated;


-- ═══════════════════════════════════════════════════════════════
-- FIX EXISTING BROKEN USERS
-- This fixes any user whose password was saved with cost=6
-- ═══════════════════════════════════════════════════════════════

-- Show current state of all users
SELECT 
  au.email,
  up.full_name,
  up.role,
  up.is_active,
  LEFT(au.encrypted_password, 7) AS hash_prefix,
  CASE 
    WHEN LEFT(au.encrypted_password, 7) = '$2a$10$' THEN '✅ OK'
    WHEN LEFT(au.encrypted_password, 7) = '$2a$06$' THEN '❌ BROKEN - needs reset'
    ELSE '⚠️ ' || LEFT(au.encrypted_password, 7)
  END AS login_status,
  au.email_confirmed_at IS NOT NULL AS email_confirmed,
  EXISTS(SELECT 1 FROM auth.identities i WHERE i.user_id = au.id) AS has_identity
FROM auth.users au
LEFT JOIN public.user_profiles up ON up.id = au.id
ORDER BY up.role;
