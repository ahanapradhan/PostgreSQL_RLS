-- Create a normal role
CREATE ROLE tpch_user LOGIN PASSWORD 'tpch';

-- Grant read access
GRANT SELECT ON
    lineitem, orders, customer, supplier, nation
TO tpch_user;

-- 1. RLS predicate function
CREATE OR REPLACE FUNCTION rls_lineitem_same_region(
    p_l_orderkey BIGINT,
    p_l_suppkey  BIGINT
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

DROP POLICY IF EXISTS lineitem_same_region_policy ON lineitem;

-- 3. Create SELECT policy on lineitem
CREATE POLICY lineitem_same_region_policy
ON lineitem
FOR SELECT
USING (
    rls_lineitem_same_region(l_orderkey, l_suppkey)
);

SET ROLE tpch_user;


--EXPLAIN
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
