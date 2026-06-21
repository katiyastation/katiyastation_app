-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS - RLS RECURSION FIX
-- Run this in your Supabase SQL editor to fix the infinite recursion error.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. DEFINE A SECURITY DEFINER ROLE GETTER ──────────────────
-- SECURITY DEFINER bypasses RLS checks, breaking the recursion loop.
CREATE OR REPLACE FUNCTION public.get_user_role(user_id UUID)
RETURNS TEXT AS $$
  SELECT role FROM public.user_profiles WHERE id = user_id;
$$ LANGUAGE sql SECURITY DEFINER;


-- ── 2. DROP EXISTING POLICIES ON USER_PROFILES ────────────────
DROP POLICY IF EXISTS "Users can read their own profile" ON public.user_profiles;
DROP POLICY IF EXISTS "Only super_admin can insert profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Super admin or self update" ON public.user_profiles;
DROP POLICY IF EXISTS "Only super_admin can delete profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Allow authenticated users to read profiles" ON public.user_profiles;
DROP POLICY IF EXISTS "Allow super admins or own profile modification" ON public.user_profiles;


-- ── 3. RE-CREATE POLICIES USING THE FUNCTION ─────────────────

-- Select: Users can view their own profile, or super_admin / branch_manager can view all profiles
CREATE POLICY "Users can read their own profile"
ON public.user_profiles FOR SELECT
TO authenticated
USING (
  id = auth.uid()
  OR public.get_user_role(auth.uid()) IN ('super_admin', 'branch_manager')
);

-- Insert: Only super admin can manually insert profiles
CREATE POLICY "Only super_admin can insert profiles"
ON public.user_profiles FOR INSERT
TO authenticated
WITH CHECK (
  public.get_user_role(auth.uid()) = 'super_admin'
);

-- Update: Users can update their own profile, or super admin can update any profile
CREATE POLICY "Super admin or self update"
ON public.user_profiles FOR UPDATE
TO authenticated
USING (
  id = auth.uid()
  OR public.get_user_role(auth.uid()) = 'super_admin'
);

-- Delete: Only super admin can delete profiles
CREATE POLICY "Only super_admin can delete profiles"
ON public.user_profiles FOR DELETE
TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin'
);


-- ── 4. UPDATE GENERAL POLICY ON OTHER TABLES FOR BRANCH ISOLATION ──
-- Replace direct subqueries with get_user_role(auth.uid())

DROP POLICY IF EXISTS "Branch isolation on restaurant_tables" ON public.restaurant_tables;
CREATE POLICY "Branch isolation on restaurant_tables" ON public.restaurant_tables FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on table_sessions" ON public.table_sessions;
CREATE POLICY "Branch isolation on table_sessions" ON public.table_sessions FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on kots" ON public.kots;
CREATE POLICY "Branch isolation on kots" ON public.kots FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on bills" ON public.bills;
CREATE POLICY "Branch isolation on bills" ON public.bills FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on inventory_items" ON public.inventory_items;
CREATE POLICY "Branch isolation on inventory_items" ON public.inventory_items FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on bar_stock" ON public.bar_stock;
CREATE POLICY "Branch isolation on bar_stock" ON public.bar_stock FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on suppliers" ON public.suppliers;
CREATE POLICY "Branch isolation on suppliers" ON public.suppliers FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

DROP POLICY IF EXISTS "Branch isolation on credit_records" ON public.credit_records;
CREATE POLICY "Branch isolation on credit_records" ON public.credit_records FOR ALL TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);
