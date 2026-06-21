-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — MENU CATEGORIES & ITEMS RLS FIX
-- Run this in your Supabase SQL Editor to allow Branch Managers
-- and Cashiers to add/edit menu categories and items.
-- ═══════════════════════════════════════════════════════════════

-- ── 1. ENABLE ROW LEVEL SECURITY ──
ALTER TABLE public.menu_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;


-- ── 2. DROP ALL POTENTIAL CONFLICTING POLICIES ──
DROP POLICY IF EXISTS "Branch isolation on menu_categories" ON public.menu_categories;
DROP POLICY IF EXISTS "Allow authenticated read menu_categories" ON public.menu_categories;
DROP POLICY IF EXISTS "Allow managers to insert menu_categories" ON public.menu_categories;
DROP POLICY IF EXISTS "Only super_admin can modify menu_categories" ON public.menu_categories;

DROP POLICY IF EXISTS "Branch isolation on menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Allow authenticated read menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Allow managers to insert menu_items" ON public.menu_items;
DROP POLICY IF EXISTS "Only super_admin can modify menu_items" ON public.menu_items;


-- ── 3. CREATE NEW BRANCH-ISOLATED POLICIES FOR MENU CATEGORIES ──
-- Users can view and modify categories belonging to their branch.
-- Super admins can view and modify all categories.
CREATE POLICY "Branch isolation on menu_categories" 
ON public.menu_categories 
FOR ALL 
TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
)
WITH CHECK (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);


-- ── 4. CREATE NEW BRANCH-ISOLATED POLICIES FOR MENU ITEMS ──
-- Users can view and modify menu items belonging to their branch.
-- Super admins can view and modify all menu items.
CREATE POLICY "Branch isolation on menu_items" 
ON public.menu_items 
FOR ALL 
TO authenticated
USING (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
)
WITH CHECK (
  public.get_user_role(auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);


-- ── 5. VERIFY CURRENT RLS STATE ──
SELECT 
  tablename, 
  rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
  AND tablename IN ('menu_categories', 'menu_items');
