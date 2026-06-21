-- ═══════════════════════════════════════════════════════════════
-- CREATE sanjaygupta@gmail.com as branch_manager
-- Password: Iphone@123
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_user_id  UUID;
  v_now      TIMESTAMPTZ := NOW();
  v_email    TEXT  := 'sanjaygupta@gmail.com';
  v_password TEXT  := 'Iphone@123';
  v_name     TEXT  := 'Sanjay Gupta';
  v_role     TEXT  := 'branch_manager';
  v_branch   UUID;
BEGIN

  -- Get first branch
  SELECT id INTO v_branch FROM public.branches LIMIT 1;

  -- ── CASE A: User already in auth.users → just fix password + profile ──
  IF EXISTS (SELECT 1 FROM auth.users WHERE email = lower(v_email)) THEN

    SELECT id INTO v_user_id FROM auth.users WHERE email = lower(v_email);

    -- Fix password with correct cost=10
    UPDATE auth.users SET
      encrypted_password = crypt(v_password, gen_salt('bf', 10)),
      email_confirmed_at = COALESCE(email_confirmed_at, v_now),
      updated_at = v_now
    WHERE id = v_user_id;

    RAISE NOTICE 'User already exists. Password updated for: %', v_email;

  -- ── CASE B: User does NOT exist → create fresh ──
  ELSE

    v_user_id := gen_random_uuid();

    -- 1. Create in auth.users
    INSERT INTO auth.users (
      id, aud, role, email,
      encrypted_password,
      email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token,
      is_sso_user
    ) VALUES (
      v_user_id, 'authenticated', 'authenticated', lower(v_email),
      crypt(v_password, gen_salt('bf', 10)),
      v_now,
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', v_name, 'role', v_role),
      v_now, v_now, '', '', false
    );

    -- 2. Create identity (try TEXT id first for newer Supabase)
    BEGIN
      EXECUTE format(
        'INSERT INTO auth.identities
           (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
         VALUES
           ($1::text, $2::text, $3, $4, ''email'', $5, $5, $5)'
      ) USING v_user_id, v_user_id, v_user_id,
              jsonb_build_object('sub', v_user_id::text, 'email', lower(v_email)),
              v_now;
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Identity insert attempt 2 (UUID id)...';
      INSERT INTO auth.identities
        (id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      VALUES
        (gen_random_uuid(), v_user_id::text, v_user_id,
         jsonb_build_object('sub', v_user_id::text, 'email', lower(v_email)),
         'email', v_now, v_now, v_now);
    END;

    RAISE NOTICE 'New user created in auth.users: %', v_email;
  END IF;

  -- 3. Upsert profile with correct role
  INSERT INTO public.user_profiles
    (id, full_name, role, branch_id, is_active, created_at, updated_at)
  VALUES
    (v_user_id, v_name, v_role, v_branch, true, v_now, v_now)
  ON CONFLICT (id) DO UPDATE SET
    full_name  = v_name,
    role       = v_role,
    branch_id  = COALESCE(v_branch, public.user_profiles.branch_id),
    is_active  = true,
    updated_at = v_now;

  RAISE NOTICE 'Profile set: role=branch_manager, active=true';

END $$;


-- ── Verify everything is correct ──────────────────────────────
SELECT
  au.email,
  up.full_name,
  up.role,
  up.is_active,
  LEFT(au.encrypted_password, 7)              AS hash_prefix,
  CASE LEFT(au.encrypted_password, 7)
    WHEN '$2a$10$' THEN '✅ Password OK'
    ELSE '❌ Wrong hash: ' || LEFT(au.encrypted_password, 7)
  END                                          AS password_status,
  au.email_confirmed_at IS NOT NULL           AS email_confirmed,
  EXISTS(
    SELECT 1 FROM auth.identities i
    WHERE i.user_id = au.id
  )                                            AS has_identity
FROM auth.users au
LEFT JOIN public.user_profiles up ON up.id = au.id
WHERE au.email = 'sanjaygupta@gmail.com';
