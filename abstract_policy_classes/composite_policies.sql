-- OR
-- P1b OR P1c
/* ---------------------------------------------------------
  Lineitem visible only if either supplier and customer
   belong to the same nation and order priority is high
or are from different nations but same region
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN orders   o  ON l.l_orderkey = o.o_orderkey
JOIN customer c  ON o.o_custkey = c.c_custkey
JOIN supplier s  ON l.l_suppkey = s.s_suppkey
JOIN nation   n1 ON c.c_nationkey = n1.n_nationkey
JOIN nation   n2 ON s.s_nationkey = n2.n_nationkey
JOIN region   r1 ON n1.n_regionkey = r1.r_regionkey
JOIN region   r2 ON n2.n_regionkey = r2.r_regionkey
WHERE
(
    -- Case 1: Same nation AND high priority
    (c.c_nationkey = s.s_nationkey
     AND o.o_orderpriority IN ('1-URGENT', '2-HIGH'))
)
OR
(
    -- Case 2: Different nations but same region
    (c.c_nationkey <> s.s_nationkey
     AND r1.r_regionkey = r2.r_regionkey)
);


-- AND
-- P2a AND P2c
/*-----------------------------------------
Customers who 
have at least one finalized order AND 
have at least one order supplied by a supplier from a different nation but within the same region as the customer.
-------------------------------------------------------------------------*/
SELECT c.*
FROM customer c
WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.o_custkey = c.c_custkey
      AND o.o_orderstatus = 'F'
)
AND EXISTS (
    SELECT 1
    FROM orders o
    JOIN lineitem l 
         ON l.l_orderkey = o.o_orderkey
    JOIN supplier s 
         ON s.s_suppkey = l.l_suppkey
    JOIN nation ns 
         ON ns.n_nationkey = s.s_nationkey
    JOIN nation nc 
         ON nc.n_nationkey = c.c_nationkey
    WHERE o.o_custkey = c.c_custkey
      AND ns.n_regionkey = nc.n_regionkey
      AND ns.n_nationkey <> nc.n_nationkey
);
