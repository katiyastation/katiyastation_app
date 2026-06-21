-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — AUTH CONFIRMATION FIX (GENERATED COLUMN)
-- Run this in your Supabase SQL Editor.
-- ═══════════════════════════════════════════════════════════════

-- ── STEP 1: Fix all existing users ──
-- Since confirmed_at is a generated column, we only update email_confirmed_at.
-- PostgreSQL will automatically calculate confirmed_at!
UPDATE auth.users
SET 
  email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
  updated_at = NOW()
WHERE email_confirmed_at IS NULL;


-- ── STEP 2: Recreate the admin user creation RPC function ──
-- Exclude "confirmed_at" from the INSERT/UPDATE statements since it is generated automatically.
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

  -- Hash password with bcrypt cost=10 (GoTrue requirement)
  v_encrypted_pw := crypt(p_password, gen_salt('bf', 10));

  -- Insert into auth.users (excluding confirmed_at since it is a GENERATED column)
  INSERT INTO auth.users (
    id, 
    aud, 
    role, 
    email,
    encrypted_password,
    email_confirmed_at,       -- ✅ Setting this automatically populates confirmed_at!
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
    v_now,
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', p_full_name, 'role', p_role),
    v_now, 
    v_now,
    '', 
    '',
    false
  );

  -- Insert into auth.identities
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
      v_user_id::text,
      v_user_id::text,
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
  EXCEPTION WHEN OTHERS THEN
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
      gen_random_uuid(),
      v_user_id::text,
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
  END;

  -- Upsert user profile
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


-- ── STEP 3: Verify confirmation status ──
SELECT 
  email,
  confirmed_at,                -- ✅ Will be automatically populated by database trigger/generation
  email_confirmed_at,
  CASE 
    WHEN confirmed_at IS NOT NULL AND email_confirmed_at IS NOT NULL THEN '✅ ACTIVE & CONFIRMED'
    ELSE '❌ UNCONFIRMED (Will fail to log in)'
  END AS login_status
FROM auth.users
WHERE email = 'sanjaygupta@gmail.com';
