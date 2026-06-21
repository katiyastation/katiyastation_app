-- ═══════════════════════════════════════════════════════════════
-- CREATE BRANCH MANAGER: sanjaygupta@gmail.com
-- Password: BranchManager@123  (change this if you want)
-- Run this in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_user_id     UUID := gen_random_uuid();
  v_identity_id UUID := gen_random_uuid();
  v_now         TIMESTAMPTZ := NOW();
  v_email       TEXT := 'sanjaygupta@gmail.com';
  v_password    TEXT := 'Iphone@123';
  v_full_name   TEXT := 'Sanjay Gupta';
  v_role        TEXT := 'branch_manager';
  v_branch_id   UUID;
BEGIN

  -- Get first active branch (assign branch manager to it)
  SELECT id INTO v_branch_id FROM public.branches WHERE is_active = true LIMIT 1;

  -- If user already exists, just update their role and profile
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = lower(v_email)) THEN
    
    -- Get existing user id
    SELECT id INTO v_user_id FROM auth.users WHERE email = lower(v_email);
    
    -- Update password with correct bcrypt cost=10
    UPDATE auth.users
    SET 
      encrypted_password = crypt(v_password, gen_salt('bf', 10)),
      email_confirmed_at = COALESCE(email_confirmed_at, v_now),
      updated_at         = v_now
    WHERE id = v_user_id;

    -- Update or insert user profile with branch_manager role
    INSERT INTO public.user_profiles (id, full_name, role, branch_id, is_active, created_at, updated_at)
    VALUES (v_user_id, v_full_name, v_role, v_branch_id, true, v_now, v_now)
    ON CONFLICT (id) DO UPDATE
      SET role       = v_role,
          full_name  = v_full_name,
          branch_id  = COALESCE(v_branch_id, public.user_profiles.branch_id),
          is_active  = true,
          updated_at = v_now;

    RAISE NOTICE '✅ Existing user updated: % → role=branch_manager, password reset', v_email;

  ELSE
    
    -- Create NEW user in auth.users
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
      lower(v_email),
      crypt(v_password, gen_salt('bf', 10)),   -- ✅ cost=10 correct
      v_now,
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', v_full_name, 'role', v_role),
      v_now, v_now,
      '', '',
      false
    );

    -- Create identity (required for email/password login)
    INSERT INTO auth.identities (
      id, provider_id, user_id,
      identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      v_identity_id,
      v_user_id::text,
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', lower(v_email)),
      'email',
      v_now, v_now, v_now
    );

    -- Create user profile
    INSERT INTO public.user_profiles (id, full_name, role, branch_id, is_active, created_at, updated_at)
    VALUES (v_user_id, v_full_name, v_role, v_branch_id, true, v_now, v_now)
    ON CONFLICT (id) DO UPDATE
      SET role      = v_role,
          full_name = v_full_name,
          branch_id = COALESCE(v_branch_id, public.user_profiles.branch_id),
          is_active = true,
          updated_at = v_now;

    RAISE NOTICE '✅ New user created: % → role=branch_manager', v_email;
  END IF;

END $$;


-- ── Verify: confirm the user exists with correct role and hash ──
SELECT 
  au.email,
  up.full_name,
  up.role,
  up.is_active,
  b.name AS branch_name,
  LEFT(au.encrypted_password, 7) AS hash_prefix,
  CASE 
    WHEN LEFT(au.encrypted_password, 7) = '$2a$10$' THEN '✅ Password OK'
    ELSE '❌ Password hash wrong'
  END AS password_status,
  au.email_confirmed_at IS NOT NULL AS email_confirmed
FROM auth.users au
JOIN public.user_profiles up ON up.id = au.id
LEFT JOIN public.branches b ON b.id = up.branch_id
WHERE au.email = 'sanjaygupta@gmail.com';
