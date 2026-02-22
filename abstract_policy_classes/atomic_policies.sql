-- P1: Attribute/Join predicate
--------------------------------
/* ---------------------------------------------------------
   Supplier visible only if supplier
          has shipped items within a time frame
   --------------------------------------------------------- */
SELECT s.*
FROM supplier s
JOIN lineitem l ON l.l_suppkey = s.s_suppkey
WHERE l.l_shipdate >= DATE '1995-05-05' - INTERVAL '180' DAY;



/* ---------------------------------------------------------
   Lineitem visible only if supplier and customer
   belong to the same nation and order priority is high
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN orders o 
     ON o.o_orderkey = l.l_orderkey
JOIN customer c 
     ON c.c_custkey = o.o_custkey
JOIN supplier s 
     ON s.s_suppkey = l.l_suppkey
WHERE s.s_nationkey = c.c_nationkey
  AND o.o_orderpriority IN ('1-URGENT', '2-HIGH');

/* ---------------------------------------------------------
  Lineitem visible only if supplier and customer
        are from different nations but same region
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN supplier s ON s.s_suppkey = l.l_suppkey
JOIN orders o ON o.o_orderkey = l.l_orderkey
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN nation ns ON ns.n_nationkey = s.s_nationkey
JOIN nation nc ON nc.n_nationkey = c.c_nationkey
WHERE ns.n_nationkey <> nc.n_nationkey
  AND ns.n_regionkey = nc.n_regionkey;
----================================
-- P2: Existence/Semi-Join
--------------------------------
/* ---------------------------------------------------------
   Customer visible only if at least one completed order
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.o_custkey = c.c_custkey
      AND o.o_orderstatus = 'F'
);

/* ---------------------------------------------------------
   Orders visible only if they contain at least one
   late-shipped lineitem with discount > 5%
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
WHERE EXISTS (
    SELECT 1
    FROM lineitem l
    WHERE l.l_orderkey = o.o_orderkey
      AND l.l_shipdate > l.l_commitdate
      AND l.l_discount > 0.05
);


/* ---------------------------------------------------------
   Customer visible only if they have at least one order
   containing a lineitem supplied by a supplier from
   a different nation but same region as the customer
   --------------------------------------------------------- */

SELECT c.*
FROM customer c
WHERE EXISTS (
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

----================================
-- P3: Universal/Anti-existence
--------------------------------
/* ---------------------------------------------------------
   Part visible only if it has never been ordered
        in quantities greater than 200
   --------------------------------------------------------- */
SELECT p.*
FROM part p
WHERE NOT EXISTS (
    SELECT 1
    FROM lineitem l
    WHERE l.l_partkey = p.p_partkey
      AND l.l_quantity > 200
);

/* ---------------------------------------------------------
   Supplier visible only if they have never supplied
        a part with retail price below 500
   --------------------------------------------------------- */
SELECT s.*
FROM supplier s
WHERE NOT EXISTS (
    SELECT 1
    FROM partsupp ps
    JOIN part p ON p.p_partkey = ps.ps_partkey
    WHERE ps.ps_suppkey = s.s_suppkey
      AND p.p_retailprice < 500
);

/* ---------------------------------------------------------
   Customer visible only if all their orders have
        at least one lineitem shipped via TRUCK or MAIL
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
WHERE NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.o_custkey = c.c_custkey
      AND NOT EXISTS (
          SELECT 1
          FROM lineitem l
          WHERE l.l_orderkey = o.o_orderkey
            AND l.l_shipmode IN ('TRUCK', 'MAIL')
      )
);
----================================
-- P4: Group/Agg
--------------------------------
/* ---------------------------------------------------------
   Customer visible only if total account balance > 0
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
GROUP BY c.c_custkey,
         c.c_name,
         c.c_address,
         c.c_nationkey,
         c.c_phone,
         c.c_acctbal,
         c.c_mktsegment,
         c.c_comment
HAVING SUM(c.c_acctbal) > 0;

/* ---------------------------------------------------------
   Orders visible only if total revenue > 100000
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN lineitem l
     ON l.l_orderkey = o.o_orderkey
GROUP BY o.o_orderkey,
         o.o_custkey,
         o.o_orderstatus,
         o.o_totalprice,
         o.o_orderdate,
         o.o_orderpriority,
         o.o_clerk,
         o.o_shippriority,
         o.o_comment
HAVING SUM(l.l_extendedprice * (1 - l.l_discount)) > 100000;

/* ---------------------------------------------------------
   Customer visible only if total revenue from suppliers
   in same region exceeds 200000
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o
     ON o.o_custkey = c.c_custkey
JOIN lineitem l
     ON l.l_orderkey = o.o_orderkey
JOIN supplier s
     ON s.s_suppkey = l.l_suppkey
JOIN nation ns
     ON ns.n_nationkey = s.s_nationkey
JOIN nation nc
     ON nc.n_nationkey = c.c_nationkey
GROUP BY c.c_custkey,
         c.c_name,
         c.c_address,
         c.c_nationkey,
         c.c_phone,
         c.c_acctbal,
         c.c_mktsegment,
         c.c_comment
HAVING SUM(
        CASE 
           WHEN ns.n_regionkey = nc.n_regionkey
           THEN l.l_extendedprice * (1 - l.l_discount)
           ELSE 0
        END
       ) > 200000;
----================================
-- P5: Statistical
--------------------------------
/* ---------------------------------------------------------
   Lineitem visible only if its order date is closer
        to ship date than to receipt date
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN orders o ON o.o_orderkey = l.l_orderkey
WHERE ABS(o.o_orderdate - l.l_shipdate)
    < ABS(o.o_orderdate - l.l_receiptdate);



/* ---------------------------------------------------------
  Lineitem visible only if its shipping delay
        exceeds the average delay for that ship mode
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
WHERE (l.l_receiptdate - l.l_shipdate) >
      (
        SELECT AVG(l2.l_receiptdate - l2.l_shipdate)
        FROM lineitem l2
        WHERE l2.l_shipmode = l.l_shipmode
      );



/* ---------------------------------------------------------
   Lineitem visible only if its supplier’s nation
        has higher total export value than import value
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN supplier s ON s.s_suppkey = l.l_suppkey
JOIN nation n ON n.n_nationkey = s.s_nationkey
WHERE
(
    SELECT SUM(lx.l_extendedprice * (1 - lx.l_discount))
    FROM lineitem lx
    JOIN supplier sx ON sx.s_suppkey = lx.l_suppkey
    WHERE sx.s_nationkey = n.n_nationkey
)
>
(
    SELECT SUM(ly.l_extendedprice * (1 - ly.l_discount))
    FROM lineitem ly
    JOIN orders oy ON oy.o_orderkey = ly.l_orderkey
    JOIN customer cy ON cy.c_custkey = oy.o_custkey
    WHERE cy.c_nationkey = n.n_nationkey
);
----================================
