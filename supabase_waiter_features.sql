-- ═══════════════════════════════════════════════════════════════
-- KATIYA STATION RMS — WAITER FEATURES SCHEMA PATCH
-- Run this in Supabase SQL Editor to enable:
--   • Hold Orders (on_hold column)
--   • Merge/Split Tables (no schema change needed)
--   • Real-time subscriptions on all key tables
--   • Fix bills table columns (invoice_number, table_id, etc.)
-- ═══════════════════════════════════════════════════════════════

-- ── 1. Add on_hold to table_sessions ─────────────────────────
ALTER TABLE public.table_sessions 
  ADD COLUMN IF NOT EXISTS on_hold BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS hold_reason TEXT;

-- ── 2. Fix kots table — add table_id if missing ──────────────
ALTER TABLE public.kots
  ADD COLUMN IF NOT EXISTS table_id UUID REFERENCES public.restaurant_tables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS waiter_name TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- ── 3. Fix kot_items — add unit_price if missing ─────────────
ALTER TABLE public.kot_items
  ADD COLUMN IF NOT EXISTS unit_price NUMERIC DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS menu_item_name TEXT;

-- ── 4. Fix bills table — add columns used by Flutter app ──────
ALTER TABLE public.bills
  ADD COLUMN IF NOT EXISTS invoice_number TEXT,
  ADD COLUMN IF NOT EXISTS table_id UUID REFERENCES public.restaurant_tables(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cashier_name TEXT,
  ADD COLUMN IF NOT EXISTS customer_name TEXT,
  ADD COLUMN IF NOT EXISTS customer_phone TEXT,
  ADD COLUMN IF NOT EXISTS amount_paid NUMERIC DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS change_amount NUMERIC DEFAULT 0.0;

-- ── 5. Fix restaurant_tables — add columns used by Flutter app ─
ALTER TABLE public.restaurant_tables
  ADD COLUMN IF NOT EXISTS bill_requested BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS bill_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS is_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS description TEXT;

-- ── 6. Fix table_sessions — add columns used by Flutter app ───
ALTER TABLE public.table_sessions
  ADD COLUMN IF NOT EXISTS bill_requested BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS bill_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS waiter_name TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT;

-- ── 7. Fix credit_records — add columns used by Flutter app ───
ALTER TABLE public.credit_records
  ADD COLUMN IF NOT EXISTS customer_name TEXT,
  ADD COLUMN IF NOT EXISTS customer_phone TEXT,
  ADD COLUMN IF NOT EXISTS credit_amount NUMERIC DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS paid_amount NUMERIC DEFAULT 0.0;

-- ── 8. Enable Realtime on all key operational tables ──────────
-- Safe: only adds a table to the publication if it's not already a member.
DO $$
DECLARE
  tbl TEXT;
BEGIN
  FOREACH tbl IN ARRAY ARRAY[
    'restaurant_tables',
    'table_sessions',
    'kots',
    'kot_items',
    'bills',
    'menu_categories',
    'menu_items'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1
      FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime'
        AND schemaname = 'public'
        AND tablename = tbl
    ) THEN
      EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', tbl);
    END IF;
  END LOOP;
END;
$$;

-- ── 9. RLS policies for kot_items (if not already set) ────────
ALTER TABLE public.kot_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Branch isolation on kot_items" ON public.kot_items;
CREATE POLICY "Branch isolation on kot_items"
ON public.kot_items FOR ALL TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.kots k
    WHERE k.id = kot_items.kot_id
    AND (
      public.get_user_role(auth.uid()) = 'super_admin' OR 
      k.branch_id = get_user_branch_id()
    )
  )
);

-- ── 10. Verify the changes ─────────────────────────────────────
SELECT 
  table_name, 
  column_name, 
  data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('table_sessions', 'kots', 'kot_items', 'bills', 'restaurant_tables')
ORDER BY table_name, column_name;
