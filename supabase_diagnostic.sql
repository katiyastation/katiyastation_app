-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — SYSTEM DIAGNOSTIC SQL
-- Run this entire script in your Supabase SQL Editor.
-- It will analyze the state of your authentication tables,
-- profiles, and constraints, showing exactly why they are out of sync.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. CHECK FOR PROFILE ORPHANS (PROFILES WITH NO AUTH USER) ──
SELECT 
  up.id AS profile_id,
  up.full_name AS profile_name,
  up.role AS profile_role,
  up.created_at AS profile_created_at,
  au.id AS auth_user_id,
  CASE 
    WHEN au.id IS NULL THEN '❌ ORPHANED PROFILE (No matching Auth User!)'
    ELSE '✅ CONNECTED (Auth User exists)'
  END AS status
FROM public.user_profiles up
LEFT JOIN auth.users au ON au.id = up.id
ORDER BY up.created_at DESC;


-- ── 2. CHECK FOREIGN KEY CONSTRAINTS ON USER_PROFILES ──
-- This checks if the references to auth.users exists and is enforced.
SELECT 
  tc.constraint_name, 
  tc.table_name, 
  kcu.column_name, 
  ccu.table_name AS foreign_table_name,
  ccu.column_name AS foreign_column_name 
FROM information_schema.table_constraints AS tc 
JOIN information_schema.key_column_usage AS kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage AS ccu
  ON ccu.constraint_name = tc.constraint_name
WHERE tc.table_schema = 'public' 
  AND tc.table_name = 'user_profiles'
  AND tc.constraint_type = 'FOREIGN KEY';


-- ── 3. LIST ALL AUTH USERS AND THEIR HASHES ──
SELECT 
  id,
  email,
  aud,
  role,
  LEFT(encrypted_password, 7) AS password_hash_prefix,
  email_confirmed_at,
  created_at,
  updated_at
FROM auth.users
ORDER BY created_at DESC;


-- ── 4. LIST ALL IDENTITIES ──
SELECT 
  id,
  user_id,
  identity_data,
  provider,
  created_at
FROM auth.identities
ORDER BY created_at DESC;
