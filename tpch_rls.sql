
create role rls_user with login; -- with password

grant select on lineitem to rls_user;
grant select on orders to rls_user;
grant select on nation to rls_user;
grant select on supplier to rls_user;
grant select on part to rls_user;
grant select on partsupp to rls_user;
grant select on customer to rls_user;
grant select on region to rls_user;



-- Enable RLS
ALTER TABLE supplier ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders   ENABLE ROW LEVEL SECURITY;
ALTER TABLE lineitem ENABLE ROW LEVEL SECURITY;

-- 1) Supplier: exclude blacklisted (by s_comment)
DROP POLICY IF EXISTS p_supplier_not_blacklisted ON supplier;
CREATE POLICY p_supplier_not_blacklisted ON supplier
FOR SELECT
TO rls_user
USING (s_comment IS NULL OR s_comment NOT ILIKE '%blacklist%');

-- 1b) Propagate supplier blacklist to lineitem
DROP POLICY IF EXISTS p_li_supplier_not_blacklisted ON lineitem;
CREATE POLICY p_li_supplier_not_blacklisted ON lineitem
FOR SELECT
TO rls_user
USING (NOT EXISTS (
  SELECT 1 FROM supplier s
  WHERE s.s_suppkey = lineitem.l_suppkey
    AND s.s_comment ILIKE '%blacklist%'
));

-- 2) Lineitem: remove sensitive comments
DROP POLICY IF EXISTS p_li_no_sensitive_comments ON lineitem;
CREATE POLICY p_li_no_sensitive_comments ON lineitem
FOR SELECT
TO rls_user
USING (
  l_comment IS NULL OR l_comment NOT ILIKE ANY (ARRAY[
    '%careful%','%confidential%','%vip%'
  ])
);

-- 3) Next-30-days windows
-- Orders having at least one line shipping in next 30 days
DROP POLICY IF EXISTS p_orders_next_30d ON orders;
CREATE POLICY p_orders_next_30d ON orders
FOR SELECT
TO rls_user
USING (EXISTS (
  SELECT 1 FROM lineitem li
  WHERE li.l_orderkey = orders.o_orderkey
    AND li.l_shipdate BETWEEN DATE '1995-01-01' AND DATE '1995-01-01' + INTERVAL '30 days'
));
-- Lineitems shipping in next 30 days
DROP POLICY IF EXISTS p_li_next_30d ON lineitem;
CREATE POLICY p_li_next_30d ON lineitem
FOR SELECT
TO rls_user
USING (l_shipdate BETWEEN DATE '1995-01-01' AND DATE '1995-01-01' + INTERVAL '30 days');

-- 4) Geo slice: suppliers & customers only in EUROPE/ASIA
DROP POLICY IF EXISTS p_supplier_region ON supplier;
CREATE POLICY p_supplier_region ON supplier
FOR SELECT
TO rls_user
USING (EXISTS (
  SELECT 1
  FROM nation n JOIN region r ON n.n_regionkey = r.r_regionkey
  WHERE n.n_nationkey = supplier.s_nationkey
    AND r.r_name IN ('EUROPE','ASIA')
));
DROP POLICY IF EXISTS p_customer_region ON customer;
CREATE POLICY p_customer_region ON customer
FOR SELECT
TO rls_user
USING (EXISTS (
  SELECT 1
  FROM nation n JOIN region r ON n.n_regionkey = r.r_regionkey
  WHERE n.n_nationkey = customer.c_nationkey
    AND r.r_name IN ('EUROPE','ASIA')
));

-- 5) Customer segments allowlist
DROP POLICY IF EXISTS p_customer_segments ON customer;
CREATE POLICY p_customer_segments ON customer
FOR SELECT
TO rls_user
USING (c_mktsegment IN ('AUTOMOBILE','MACHINERY'));


----- new
-- ============================================================
-- RLS policy: lineitem rows visible only when
-- customer and supplier belong to the same region
-- ============================================================

-- 1. RLS predicate function
CREATE OR REPLACE FUNCTION rls_lineitem_same_region(
    p_l_orderkey INTEGER,
    p_l_suppkey  INTEGER
)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM orders o
        JOIN customer c   ON c.c_custkey    = o.o_custkey
        JOIN supplier s   ON s.s_suppkey    = p_l_suppkey
        JOIN nation nc    ON nc.n_nationkey = c.c_nationkey
        JOIN nation ns    ON ns.n_nationkey = s.s_nationkey
        WHERE o.o_orderkey = p_l_orderkey
          AND nc.n_regionkey = ns.n_regionkey
    );
$$;

-- 2. Enable RLS on lineitem
ALTER TABLE lineitem ENABLE ROW LEVEL SECURITY;

-- Optional but recommended: enforce RLS even for table owner
ALTER TABLE lineitem FORCE ROW LEVEL SECURITY;

-- 3. Create SELECT policy on lineitem
CREATE POLICY lineitem_same_region_policy
ON lineitem
FOR SELECT
USING (
    rls_lineitem_same_region(l_orderkey, l_suppkey)
);

-- ============================================================
-- End of RLS policy
-- ============================================================
EXPLAIN
SELECT
    l.l_orderkey,
    SUM(l.l_extendedprice * (1 - l.l_discount)) AS revenue,
    o.o_orderdate,
    o.o_shippriority
FROM
    customer c
JOIN orders o
    ON c.c_custkey = o.o_custkey
JOIN lineitem l
    ON l.l_orderkey = o.o_orderkey
WHERE
    c.c_mktsegment = 'BUILDING'
    AND o.o_orderdate < DATE '1995-03-15'
    AND l.l_shipdate > DATE '1995-03-15'
GROUP BY
    l.l_orderkey,
    o.o_orderdate,
    o.o_shippriority
ORDER BY
    revenue DESC,
    o.o_orderdate
LIMIT 10;
