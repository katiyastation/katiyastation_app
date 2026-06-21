-- KATIYA STATION RMS - COMPLETE SUPABASE DATABASE SCHEMA
-- This script sets up all 30 tables, foreign key constraints, automatic updated_at triggers, 
-- auth triggers, and Row Level Security (RLS) policies for role-based access.

-- ENABLE UUID EXTENSION
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. BRANCHES TABLE
CREATE TABLE public.branches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    city TEXT,
    address TEXT,
    phone TEXT,
    email TEXT,
    tax_reg_number TEXT,
    vat_rate NUMERIC DEFAULT 13.0,
    service_charge_rate NUMERIC DEFAULT 10.0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. USER PROFILES TABLE (Linked to Supabase Auth.users)
CREATE TABLE public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role TEXT NOT NULL CHECK (role IN ('super_admin', 'branch_manager', 'cashier', 'waiter', 'kitchen', 'inventory', 'accountant')),
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    phone TEXT,
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. RESTAURANT TABLES
CREATE TABLE public.restaurant_tables (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    table_number TEXT NOT NULL,
    section TEXT DEFAULT 'Main',
    capacity INT DEFAULT 4,
    status TEXT DEFAULT 'available' CHECK (status IN ('available', 'occupied', 'reserved', 'cleaning')),
    current_session_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(branch_id, table_number)
);

-- 4. TABLE SESSIONS
CREATE TABLE public.table_sessions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    table_id UUID NOT NULL REFERENCES public.restaurant_tables(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    session_number TEXT NOT NULL,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'closed', 'billed')),
    waiter_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    customer_id UUID,
    guest_count INT DEFAULT 1,
    total_amount NUMERIC DEFAULT 0.0,
    opened_at TIMESTAMPTZ DEFAULT NOW(),
    closed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Link back table session ID
ALTER TABLE public.restaurant_tables ADD CONSTRAINT fk_current_session FOREIGN KEY (current_session_id) REFERENCES public.table_sessions(id) ON DELETE SET NULL;

-- 5. KOTS (Kitchen Order Tickets)
CREATE TABLE public.kots (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    session_id UUID NOT NULL REFERENCES public.table_sessions(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    kot_number TEXT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'preparing', 'ready', 'served', 'cancelled')),
    waiter_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    items_count INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. MENU CATEGORIES
CREATE TABLE public.menu_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    type TEXT DEFAULT 'food' CHECK (type IN ('food', 'drink', 'bar')),
    sort_order INT DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(branch_id, name)
);

-- 7. MENU ITEMS
CREATE TABLE public.menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    category_id UUID NOT NULL REFERENCES public.menu_categories(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    price NUMERIC NOT NULL,
    cost_price NUMERIC,
    tax_rate NUMERIC DEFAULT 0.13,
    description TEXT,
    image_url TEXT,
    is_available BOOLEAN DEFAULT true,
    type TEXT DEFAULT 'food' CHECK (type IN ('food', 'drink', 'bar')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. KOT ITEMS
CREATE TABLE public.kot_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    kot_id UUID NOT NULL REFERENCES public.kots(id) ON DELETE CASCADE,
    menu_item_id UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    quantity INT NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'preparing', 'ready', 'served', 'cancelled')),
    note TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 9. BILLS
CREATE TABLE public.bills (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    session_id UUID REFERENCES public.table_sessions(id) ON DELETE SET NULL,
    bill_number TEXT NOT NULL,
    sub_total NUMERIC NOT NULL,
    discount NUMERIC DEFAULT 0.0,
    service_charge NUMERIC DEFAULT 0.0,
    vat_amount NUMERIC DEFAULT 0.0,
    total_amount NUMERIC NOT NULL,
    payment_method TEXT DEFAULT 'cash' CHECK (payment_method IN ('cash', 'card', 'esewa', 'khalti', 'fonepay', 'bank_transfer', 'credit')),
    payment_status TEXT DEFAULT 'paid' CHECK (payment_status IN ('paid', 'partial_paid', 'credit', 'refunded')),
    cashier_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. CREDIT RECORDS (Udhaaro)
CREATE TABLE public.credit_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL,
    amount NUMERIC NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'partial_paid', 'paid', 'overdue')),
    due_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 11. INVENTORY ITEMS (Ingredients & Raw Stock)
CREATE TABLE public.inventory_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    unit TEXT NOT NULL,
    current_stock NUMERIC DEFAULT 0.0,
    reorder_level NUMERIC DEFAULT 0.0,
    cost_per_unit NUMERIC,
    supplier_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 12. BAR STOCK (Liquor Assets)
CREATE TABLE public.bar_stock (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    category TEXT DEFAULT 'spirits',
    bottle_capacity_ml NUMERIC DEFAULT 750,
    current_bottles NUMERIC DEFAULT 0.0,
    pegs_ml NUMERIC DEFAULT 30,
    price_per_peg NUMERIC DEFAULT 0.0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 13. BAR TRANSACTIONS
CREATE TABLE public.bar_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.bar_stock(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('in', 'out', 'spill', 'audit')),
    quantity NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 14. SUPPLIERS
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    contact_person TEXT,
    phone TEXT,
    email TEXT,
    category TEXT,
    address TEXT,
    notes TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 15. PURCHASES
CREATE TABLE public.purchases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    total_amount NUMERIC DEFAULT 0.0,
    status TEXT DEFAULT 'completed' CHECK (status IN ('pending', 'completed', 'cancelled')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 16. PURCHASE ITEMS
CREATE TABLE public.purchase_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_id UUID NOT NULL REFERENCES public.purchases(id) ON DELETE CASCADE,
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    quantity NUMERIC NOT NULL,
    unit_cost NUMERIC NOT NULL
);

-- Link Supplier ID on Inventory Items
ALTER TABLE public.inventory_items ADD CONSTRAINT fk_item_supplier FOREIGN KEY (supplier_id) REFERENCES public.suppliers(id) ON DELETE SET NULL;

-- 17. EXPENSES
CREATE TABLE public.expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    amount NUMERIC NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 18. CUSTOMERS
CREATE TABLE public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT UNIQUE NOT NULL,
    email TEXT,
    loyalty_points INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 19. RESERVATIONS
CREATE TABLE public.reservations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    customer_name TEXT NOT NULL,
    customer_phone TEXT NOT NULL,
    guest_count INT DEFAULT 2,
    reservation_time TIMESTAMPTZ NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'arrived', 'completed', 'cancelled', 'no_show')),
    table_id UUID REFERENCES public.restaurant_tables(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 20. LOYALTY TRANSACTIONS
CREATE TABLE public.loyalty_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('earn', 'redeem')),
    points INT NOT NULL,
    purchase_amount NUMERIC DEFAULT 0.0,
    notes TEXT,
    created_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 21. STAFF MEMBERS
CREATE TABLE public.staff_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    role TEXT NOT NULL,
    phone TEXT,
    salary NUMERIC DEFAULT 0.0,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'inactive', 'terminated')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 22. ATTENDANCE
CREATE TABLE public.attendance (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    staff_id UUID NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
    date DATE NOT NULL DEFAULT CURRENT_DATE,
    clock_in TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    clock_out TIMESTAMPTZ,
    status TEXT DEFAULT 'present' CHECK (status IN ('present', 'absent', 'late', 'half_day')),
    UNIQUE(staff_id, date)
);

-- 23. SALARIES
CREATE TABLE public.salaries (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    staff_id UUID NOT NULL REFERENCES public.staff_members(id) ON DELETE CASCADE,
    amount NUMERIC NOT NULL,
    paid_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    status TEXT DEFAULT 'paid' CHECK (status IN ('paid', 'pending'))
);

-- 24. AUDIT LOGS
CREATE TABLE public.audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID REFERENCES public.branches(id) ON DELETE SET NULL,
    user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    action TEXT NOT NULL,
    table_name TEXT NOT NULL,
    row_id TEXT,
    old_values JSONB,
    new_values JSONB,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 25. SHIFT CLOSINGS (End-of-Day)
CREATE TABLE public.shift_closings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    cashier_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
    cashier_name TEXT,
    date TEXT NOT NULL,
    cash_total NUMERIC DEFAULT 0.0,
    card_total NUMERIC DEFAULT 0.0,
    esewa_total NUMERIC DEFAULT 0.0,
    khalti_total NUMERIC DEFAULT 0.0,
    fonepay_total NUMERIC DEFAULT 0.0,
    credit_total NUMERIC DEFAULT 0.0,
    refund_total NUMERIC DEFAULT 0.0,
    total_revenue NUMERIC DEFAULT 0.0,
    net_revenue NUMERIC DEFAULT 0.0,
    total_vat NUMERIC DEFAULT 0.0,
    total_discount NUMERIC DEFAULT 0.0,
    total_service_charge NUMERIC DEFAULT 0.0,
    bill_count INT DEFAULT 0,
    status TEXT DEFAULT 'pending_approval' CHECK (status IN ('pending_approval', 'approved', 'rejected')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 26. RECIPES
CREATE TABLE public.recipes (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    menu_item_id UUID UNIQUE NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    instructions TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 27. RECIPE INGREDIENTS
CREATE TABLE public.recipe_ingredients (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    recipe_id UUID NOT NULL REFERENCES public.recipes(id) ON DELETE CASCADE,
    inventory_item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    quantity NUMERIC NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(recipe_id, inventory_item_id)
);

-- 28. STOCK MOVEMENTS
CREATE TABLE public.stock_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    item_id UUID NOT NULL REFERENCES public.inventory_items(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('in', 'out', 'adjustment', 'waste')),
    quantity NUMERIC NOT NULL,
    reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 29. NOTIFICATIONS
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    branch_id UUID NOT NULL REFERENCES public.branches(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    is_read BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ── 30. AUTOMATIC UPDATED_AT TRIGGERS ──
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Apply updated_at triggers
CREATE TRIGGER update_branches_modtime BEFORE UPDATE ON public.branches FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_user_profiles_modtime BEFORE UPDATE ON public.user_profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_restaurant_tables_modtime BEFORE UPDATE ON public.restaurant_tables FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_kots_modtime BEFORE UPDATE ON public.kots FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_menu_items_modtime BEFORE UPDATE ON public.menu_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_bills_modtime BEFORE UPDATE ON public.bills FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_credit_records_modtime BEFORE UPDATE ON public.credit_records FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_inventory_items_modtime BEFORE UPDATE ON public.inventory_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_bar_stock_modtime BEFORE UPDATE ON public.bar_stock FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_suppliers_modtime BEFORE UPDATE ON public.suppliers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_purchases_modtime BEFORE UPDATE ON public.purchases FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_expenses_modtime BEFORE UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_customers_modtime BEFORE UPDATE ON public.customers FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_reservations_modtime BEFORE UPDATE ON public.reservations FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_staff_members_modtime BEFORE UPDATE ON public.staff_members FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_recipes_modtime BEFORE UPDATE ON public.recipes FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();


-- ── 31. AUTO-PROFILE GENERATION FOR NEW USER SIGNUPS ──
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.user_profiles (id, full_name, role, is_active, created_at)
  VALUES (
    new.id,
    COALESCE(new.raw_user_meta_data->>'full_name', 'New User'),
    COALESCE(new.raw_user_meta_data->>'role', 'waiter'), -- defaults to waiter
    true,
    NOW()
  );
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── 32. ROW LEVEL SECURITY (RLS) POLICIES ──
-- Enable RLS on user_profiles
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Select policies
CREATE POLICY "Allow authenticated users to read profiles"
ON public.user_profiles FOR SELECT
TO authenticated
USING (true);

-- Update policies
CREATE POLICY "Allow super admins or own profile modification"
ON public.user_profiles FOR UPDATE
TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  id = auth.uid()
);

-- Enable RLS on other operational tables to protect branch data isolation
ALTER TABLE public.restaurant_tables ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.table_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.kots ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bills ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bar_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.credit_records ENABLE ROW LEVEL SECURITY;

-- Create Branch Isolation helper
CREATE OR REPLACE FUNCTION get_user_branch_id()
RETURNS UUID AS $$
  SELECT branch_id FROM public.user_profiles WHERE id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;

-- General policy for branch data isolation:
-- Users can only view/modify data belonging to their own branch (unless super_admin)
CREATE POLICY "Branch isolation on restaurant_tables" ON public.restaurant_tables FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on table_sessions" ON public.table_sessions FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on kots" ON public.kots FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on bills" ON public.bills FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on inventory_items" ON public.inventory_items FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on bar_stock" ON public.bar_stock FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on suppliers" ON public.suppliers FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);

CREATE POLICY "Branch isolation on credit_records" ON public.credit_records FOR ALL TO authenticated
USING (
  (SELECT role FROM public.user_profiles WHERE id = auth.uid()) = 'super_admin' OR 
  branch_id = get_user_branch_id()
);
