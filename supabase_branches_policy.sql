-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS - BRANCHES TABLE RLS POLICIES
-- Run this in your Supabase SQL editor to allow Super Admins to insert/update branches.
-- ═══════════════════════════════════════════════════════════════

-- Ensure RLS is active on branches table
ALTER TABLE public.branches ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Allow authenticated users to read branches" ON public.branches;
DROP POLICY IF EXISTS "Only super admins can modify branches" ON public.branches;

-- 1. SELECT: Allow any logged in user (cashier, waiter, branch_manager, etc.) to view branches
CREATE POLICY "Allow authenticated users to read branches"
ON public.branches FOR SELECT
TO authenticated
USING (true);

-- 2. ALL: Allow only super_admin to insert, update or delete branches
CREATE POLICY "Only super admins can modify branches"
ON public.branches FOR ALL
TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin'
)
WITH CHECK (
  public.get_user_role(auth.uid()) = 'super_admin'
);
