-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — DIRECT PASSWORD FIX
-- Run this in Supabase SQL Editor (it has admin/postgres access,
-- so it bypasses RLS and can directly update auth.users)
-- ═══════════════════════════════════════════════════════════════

-- STEP 1: See all your users and their emails
-- Run this first so you can see exactly what emails exist:
SELECT 
  au.email,
  au.id,
  up.full_name,
  up.role,
  up.is_active,
  LEFT(au.encrypted_password, 7) AS pw_hash_prefix
FROM auth.users au
LEFT JOIN public.user_profiles up ON up.id = au.id
ORDER BY up.role;

-- The pw_hash_prefix column will show:
--   $2a$10$  = CORRECT (cost=10, GoTrue can verify)
--   $2a$06$  = BROKEN  (cost=6, GoTrue cannot verify → "invalid credentials")

-- ═══════════════════════════════════════════════════════════════
-- STEP 2: Reset passwords for ALL broken users at once
-- Replace each password below with the actual password you want.
-- ═══════════════════════════════════════════════════════════════

-- Update branch_manager password:
UPDATE auth.users
SET 
  encrypted_password = crypt('YourBranchManagerPassword123', gen_salt('bf', 10)),
  updated_at = NOW()
WHERE email = 'branchmanager@katiyastation.com';   -- ← replace with actual email

-- Update cashier password:
UPDATE auth.users
SET 
  encrypted_password = crypt('YourCashierPassword123', gen_salt('bf', 10)),
  updated_at = NOW()
WHERE email = 'cashier@katiyastation.com';           -- ← replace with actual email

-- Update waiter password:
UPDATE auth.users
SET 
  encrypted_password = crypt('YourWaiterPassword123', gen_salt('bf', 10)),
  updated_at = NOW()
WHERE email = 'waiter@katiyastation.com';            -- ← replace with actual email

-- ═══════════════════════════════════════════════════════════════
-- STEP 3: Verify the fix worked — run this after the UPDATEs
-- All rows should now show $2a$10$ prefix (NOT $2a$06$)
-- ═══════════════════════════════════════════════════════════════
SELECT 
  au.email,
  up.role,
  LEFT(au.encrypted_password, 7) AS pw_hash_prefix,
  CASE 
    WHEN LEFT(au.encrypted_password, 7) = '$2a$10$' THEN '✅ FIXED'
    WHEN LEFT(au.encrypted_password, 7) = '$2a$06$' THEN '❌ STILL BROKEN'
    ELSE '⚠️ UNKNOWN FORMAT'
  END AS status
FROM auth.users au
LEFT JOIN public.user_profiles up ON up.id = au.id
ORDER BY up.role;
