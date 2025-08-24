-- ======= Session “role” (masking) example =======
-- Per-session: SET app.role = 'FINANCE'|'ANALYST'|'GLOBAL';
-- ================================================

-- Enable RLS
ALTER TABLE supplier ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders   ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineitem ENABLE ROW LEVEL SECURITY;

-- 1) Supplier: exclude blacklisted (by s_comment)
DROP POLICY IF EXISTS p_supplier_not_blacklisted ON supplier;
CREATE POLICY p_supplier_not_blacklisted ON supplier
USING (s_comment IS NULL OR s_comment NOT ILIKE '%blacklist%');

-- 1b) Propagate supplier blacklist to lineitem
DROP POLICY IF EXISTS p_li_supplier_not_blacklisted ON lineitem;
CREATE POLICY p_li_supplier_not_blacklisted ON lineitem
USING (NOT EXISTS (
  SELECT 1 FROM supplier s
  WHERE s.s_suppkey = lineitem.l_suppkey
    AND s.s_comment ILIKE '%blacklist%'
));

-- 2) Lineitem: remove sensitive comments
DROP POLICY IF EXISTS p_li_no_sensitive_comments ON lineitem;
CREATE POLICY p_li_no_sensitive_comments ON lineitem
USING (
  l_comment IS NULL OR l_comment NOT ILIKE ANY (ARRAY[
    '%careful%','%confidential%','%vip%'
  ])
);

-- 3) Next-30-days windows
-- Orders having at least one line shipping in next 30 days
DROP POLICY IF EXISTS p_orders_next_30d ON orders;
CREATE POLICY p_orders_next_30d ON orders
USING (EXISTS (
  SELECT 1 FROM lineitem li
  WHERE li.l_orderkey = orders.o_orderkey
    AND li.l_shipdate BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days'
));
-- Lineitems shipping in next 30 days
DROP POLICY IF EXISTS p_li_next_30d ON lineitem;
CREATE POLICY p_li_next_30d ON lineitem
USING (l_shipdate BETWEEN CURRENT_DATE AND CURRENT_DATE + INTERVAL '30 days');

-- 4) Geo slice: suppliers & customers only in EUROPE/ASIA
DROP POLICY IF EXISTS p_supplier_region ON supplier;
CREATE POLICY p_supplier_region ON supplier
USING (EXISTS (
  SELECT 1
  FROM nation n JOIN region r ON n.n_regionkey = r.r_regionkey
  WHERE n.n_nationkey = supplier.s_nationkey
    AND r.r_name IN ('EUROPE','ASIA')
));
DROP POLICY IF EXISTS p_customer_region ON customer;
CREATE POLICY p_customer_region ON customer
USING (EXISTS (
  SELECT 1
  FROM nation n JOIN region r ON n.n_regionkey = r.r_regionkey
  WHERE n.n_nationkey = customer.c_nationkey
    AND r.r_name IN ('EUROPE','ASIA')
));

-- 5) Customer segments allowlist
DROP POLICY IF EXISTS p_customer_segments ON customer;
CREATE POLICY p_customer_segments ON customer
USING (c_mktsegment IN ('AUTOMOBILE','MACHINERY'));

-- 6) Monetary masking (role-aware views)
CREATE OR REPLACE VIEW v_orders AS
SELECT
  o_orderkey, o_custkey, o_orderstatus, o_orderdate, o_orderpriority,
  o_clerk, o_shippriority, o_comment,
  CASE WHEN current_setting('app.role', true) = 'FINANCE'
       THEN o_totalprice ELSE NULL::numeric END AS o_totalprice
FROM orders
WITH LOCAL CHECK OPTION;

CREATE OR REPLACE VIEW v_lineitem AS
SELECT
  l_orderkey, l_partkey, l_suppkey, l_linenumber, l_quantity,
  l_returnflag, l_linestatus, l_shipdate, l_commitdate, l_receiptdate,
  l_shipinstruct, l_shipmode, l_comment,
  CASE WHEN current_setting('app.role', true) = 'FINANCE'
       THEN l_extendedprice ELSE NULL::numeric END AS l_extendedprice,
  CASE WHEN current_setting('app.role', true) = 'FINANCE'
       THEN l_discount ELSE NULL::numeric END AS l_discount,
  CASE WHEN current_setting('app.role', true) = 'FINANCE'
       THEN l_tax ELSE NULL::numeric END AS l_tax
FROM lineitem
WITH LOCAL CHECK OPTION;
