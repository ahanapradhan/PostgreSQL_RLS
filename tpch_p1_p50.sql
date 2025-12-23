/* =========================================================
   TPCH ACCESS CONTROL POLICIES : P1 – P40
   ========================================================= */


/* ---------------------------------------------------------
   P1: Only see line items shipped within the last 5 years
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_shipdate >= CURRENT_DATE - INTERVAL '5' YEAR;


/* ---------------------------------------------------------
   P2: Exclude rows where l_comment contains 'carefully'
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_comment NOT LIKE '%carefully%';


/* ---------------------------------------------------------
   P3: Only allow rows where L_RETURNFLAG <> 'R'
       or L_DISCOUNT < 0.05
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_returnflag <> 'R'
   OR l_discount < 0.05;


/* ---------------------------------------------------------
   P4: Only allow rows where line is Open and not returned
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_linestatus = 'O'
  AND l_returnflag <> 'R';


/* ---------------------------------------------------------
   P5: Final price between 20,000 and 200,000
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_extendedprice * (1 - l_discount)
      BETWEEN 20000 AND 200000;


/* ---------------------------------------------------------
   P6: Ship date ≤ commit date + 30 days
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_shipdate <= l_commitdate + INTERVAL '30' DAY;


/* ---------------------------------------------------------
   P7: Receipt date ≤ commit date + 30 days
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_receiptdate <= l_commitdate + INTERVAL '30' DAY;


/* ---------------------------------------------------------
   P8: Ship mode contains AIR or RAIL
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_shipmode LIKE '%AIR%'
   OR l_shipmode LIKE '%RAIL%';


/* ---------------------------------------------------------
   P9: Tax between 0.02 and 0.06
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE l_tax BETWEEN 0.02 AND 0.06;


/* ---------------------------------------------------------
   P10: Discount between 0.02 and 0.06
        OR quantity between 10 and 30
   --------------------------------------------------------- */
SELECT *
FROM lineitem
WHERE (l_discount BETWEEN 0.02 AND 0.06)
   OR (l_quantity BETWEEN 10 AND 30);


/* ---------------------------------------------------------
   P11: Show LINEITEM only if the region of its order’s
        customer equals the region of its supplier
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN orders o ON o.o_orderkey = l.l_orderkey
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN supplier s ON s.s_suppkey = l.l_suppkey
JOIN nation nc ON nc.n_nationkey = c.c_nationkey
JOIN nation ns ON ns.n_nationkey = s.s_nationkey
WHERE nc.n_regionkey = ns.n_regionkey;


/* ---------------------------------------------------------
   P12: Orders visible if at least one lineitem has
        discount 5%-10% and discounted price > 1000
   --------------------------------------------------------- */
SELECT DISTINCT o.*
FROM orders o
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
WHERE l.l_discount BETWEEN 0.05 AND 0.10
  AND l.l_extendedprice * (1 - l.l_discount) > 1000;


/* ---------------------------------------------------------
   P13: Orders visible if customer resides in EUROPE region
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN nation n ON n.n_nationkey = c.c_nationkey
JOIN region r ON r.r_regionkey = n.n_regionkey
WHERE r.r_name = 'EUROPE';


/* ---------------------------------------------------------
   P14: Customer visible if balance > 1000
        and region = ASIA
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN nation n ON n.n_nationkey = c.c_nationkey
JOIN region r ON r.r_regionkey = n.n_regionkey
WHERE c.c_acctbal > 1000
  AND r.r_name = 'ASIA';


/* ---------------------------------------------------------
   P15: Customer visible if any order in last 90 days
        has lineitem quantity > 100
   --------------------------------------------------------- */
SELECT DISTINCT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
WHERE o.o_orderdate >= CURRENT_DATE - INTERVAL '90' DAY
  AND l.l_quantity > 100;


/* ---------------------------------------------------------
   P16: Lineitem visible if supplier sold at least 20%
        of this part to customers in same region as
        Customer#000001111
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN orders o ON o.o_orderkey = l.l_orderkey
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN nation n ON n.n_nationkey = c.c_nationkey
WHERE l.l_quantity >= 0.2 *
      (
        SELECT SUM(l2.l_quantity)
        FROM lineitem l2
        WHERE l2.l_partkey = l.l_partkey
      )
AND n.n_regionkey =
    (
      SELECT n2.n_regionkey
      FROM customer c2
      JOIN nation n2 ON n2.n_nationkey = c2.c_nationkey
      WHERE c2.c_custkey = 1111
    );


/* ---------------------------------------------------------
   P17: Customer visible if no cancelled orders and
        at least 5 orders in last 365 days
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
GROUP BY c.c_custkey
HAVING COUNT(*) >= 5
   AND MAX(o.o_orderdate) >= CURRENT_DATE - INTERVAL '365' DAY
   AND SUM(CASE WHEN o.o_orderstatus = 'C' THEN 1 ELSE 0 END) = 0;


/* ---------------------------------------------------------
   P18: Supplier visible if they supply at least one
        'Small brushed copper' part
   --------------------------------------------------------- */
SELECT DISTINCT s.*
FROM supplier s
JOIN partsupp ps ON ps.ps_suppkey = s.s_suppkey
JOIN part p ON p.p_partkey = ps.ps_partkey
WHERE p.p_name = 'Small brushed copper';


/* ---------------------------------------------------------
   P19: Part visible if at least one supplier is in EUROPE
   --------------------------------------------------------- */
SELECT DISTINCT p.*
FROM part p
JOIN partsupp ps ON ps.ps_partkey = p.p_partkey
JOIN supplier s ON s.s_suppkey = ps.ps_suppkey
JOIN nation n ON n.n_nationkey = s.s_nationkey
JOIN region r ON r.r_regionkey = n.n_regionkey
WHERE r.r_name = 'EUROPE';


/* ---------------------------------------------------------
   P20: Part visible if average supply cost < 50
   --------------------------------------------------------- */
SELECT p.*
FROM part p
JOIN partsupp ps ON ps.ps_partkey = p.p_partkey
GROUP BY p.p_partkey
HAVING AVG(ps.ps_supplycost) < 50;


/* =========================================================
   TPCH ACCESS CONTROL POLICIES : P21 – P40
   ========================================================= */


/* ---------------------------------------------------------
   P21: Orders visible only if total order revenue exceeds 100,000
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY o.o_orderkey
HAVING SUM(l.l_extendedprice * (1 - l.l_discount)) > 100000;


/* ---------------------------------------------------------
   P22: Orders visible only if all lineitems were shipped before receipt date
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
WHERE NOT EXISTS (
    SELECT 1
    FROM lineitem l
    WHERE l.l_orderkey = o.o_orderkey
      AND l.l_shipdate > l.l_receiptdate
);


/* ---------------------------------------------------------
   P23: Customer visible if they have orders from at least 3 different suppliers
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY c.c_custkey
HAVING COUNT(DISTINCT l.l_suppkey) >= 3;


/* ---------------------------------------------------------
   P24: Supplier visible if they have fulfilled orders
        for customers in at least 2 regions
   --------------------------------------------------------- */
SELECT s.*
FROM supplier s
JOIN lineitem l ON l.l_suppkey = s.s_suppkey
JOIN orders o ON o.o_orderkey = l.l_orderkey
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN nation n ON n.n_nationkey = c.c_nationkey
JOIN region r ON r.r_regionkey = n.n_regionkey
GROUP BY s.s_suppkey
HAVING COUNT(DISTINCT r.r_regionkey) >= 2;


/* ---------------------------------------------------------
   P25: Lineitem visible only if its part’s retail price
        is above the average retail price of its brand
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN part p ON p.p_partkey = l.l_partkey
WHERE p.p_retailprice >
      (
        SELECT AVG(p2.p_retailprice)
        FROM part p2
        WHERE p2.p_brand = p.p_brand
      );


/* ---------------------------------------------------------
   P26: Part visible only if supplied by more than 5 suppliers
   --------------------------------------------------------- */
SELECT p.*
FROM part p
JOIN partsupp ps ON ps.ps_partkey = p.p_partkey
GROUP BY p.p_partkey
HAVING COUNT(DISTINCT ps.ps_suppkey) > 5;


/* ---------------------------------------------------------
   P27: Supplier visible only if their average supply cost
        is below the global average supply cost
   --------------------------------------------------------- */
SELECT s.*
FROM supplier s
JOIN partsupp ps ON ps.ps_suppkey = s.s_suppkey
GROUP BY s.s_suppkey
HAVING AVG(ps.ps_supplycost) <
       (SELECT AVG(ps2.ps_supplycost) FROM partsupp ps2);


/* ---------------------------------------------------------
   P28: Orders visible only if no lineitem was shipped late
        (shipdate > commitdate)
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
WHERE NOT EXISTS (
    SELECT 1
    FROM lineitem l
    WHERE l.l_orderkey = o.o_orderkey
      AND l.l_shipdate > l.l_commitdate
);


/* ---------------------------------------------------------
   P29: Customer visible if their lifetime total order value
        exceeds their account balance
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY c.c_custkey, c.c_acctbal
HAVING SUM(l.l_extendedprice * (1 - l.l_discount)) > c.c_acctbal;


/* ---------------------------------------------------------
   P30: Lineitem visible only if supplier and customer
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


/* ---------------------------------------------------------
   P31: Part visible only if it has never been ordered
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
   P32: Supplier visible only if they have at least one
        order with priority '1-URGENT'
   --------------------------------------------------------- */
SELECT DISTINCT s.*
FROM supplier s
JOIN lineitem l ON l.l_suppkey = s.s_suppkey
JOIN orders o ON o.o_orderkey = l.l_orderkey
WHERE o.o_orderpriority = '1-URGENT';


/* ---------------------------------------------------------
   P33: Orders visible only if placed by customers with
        above-average account balance in their nation
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN customer c ON c.c_custkey = o.o_custkey
WHERE c.c_acctbal >
      (
        SELECT AVG(c2.c_acctbal)
        FROM customer c2
        WHERE c2.c_nationkey = c.c_nationkey
      );


/* ---------------------------------------------------------
   P34: Customer visible only if they placed orders
        in more than one calendar year
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
GROUP BY c.c_custkey
HAVING COUNT(DISTINCT EXTRACT(YEAR FROM o.o_orderdate)) > 1;


/* ---------------------------------------------------------
   P35: Lineitem visible only if its shipping delay
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
   P36: Part visible only if its size is above the
        average size of parts of the same type
   --------------------------------------------------------- */
SELECT p.*
FROM part p
WHERE p.p_size >
      (
        SELECT AVG(p2.p_size)
        FROM part p2
        WHERE p2.p_type = p.p_type
      );


/* ---------------------------------------------------------
   P37: Supplier visible only if they supply parts from
        at least 3 different part types
   --------------------------------------------------------- */
SELECT s.*
FROM supplier s
JOIN partsupp ps ON ps.ps_suppkey = s.s_suppkey
JOIN part p ON p.p_partkey = ps.ps_partkey
GROUP BY s.s_suppkey
HAVING COUNT(DISTINCT p.p_type) >= 3;


/* ---------------------------------------------------------
   P38: Orders visible only if total quantity ordered
        exceeds 3× the customer’s average order quantity
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY o.o_orderkey, o.o_custkey
HAVING SUM(l.l_quantity) >
       3 * (
           SELECT AVG(l2.l_quantity)
           FROM orders o2
           JOIN lineitem l2 ON l2.l_orderkey = o2.o_orderkey
           WHERE o2.o_custkey = o.o_custkey
       );


/* ---------------------------------------------------------
   P39: Customer visible only if all their orders have
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


/* ---------------------------------------------------------
   P40: Lineitem visible only if its supplier’s nation
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

/* ---------------------------------------------------------
   P41: Orders visible only if the maximum lineitem quantity
        in the order is at most twice the minimum quantity
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY o.o_orderkey
HAVING MAX(l.l_quantity) <= 2 * MIN(l.l_quantity);


/* ---------------------------------------------------------
   P42: Customer visible only if they have ordered parts
        from at least 3 different part brands
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
JOIN part p ON p.p_partkey = l.l_partkey
GROUP BY c.c_custkey
HAVING COUNT(DISTINCT p.p_brand) >= 3;


/* ---------------------------------------------------------
   P43: Supplier visible only if their supplied parts
        cover at least 2 different part sizes
   --------------------------------------------------------- */
SELECT s.*
FROM supplier s
JOIN partsupp ps ON ps.ps_suppkey = s.s_suppkey
JOIN part p ON p.p_partkey = ps.ps_partkey
GROUP BY s.s_suppkey
HAVING COUNT(DISTINCT p.p_size) >= 2;


/* ---------------------------------------------------------
   P44: Part visible only if its total ordered quantity
        exceeds the average total quantity of all parts
   --------------------------------------------------------- */
SELECT p.*
FROM part p
JOIN lineitem l ON l.l_partkey = p.p_partkey
GROUP BY p.p_partkey
HAVING SUM(l.l_quantity) >
       (
         SELECT AVG(part_qty)
         FROM (
             SELECT SUM(l2.l_quantity) AS part_qty
             FROM lineitem l2
             GROUP BY l2.l_partkey
         ) t
       );


/* ---------------------------------------------------------
   P45: Orders visible only if the customer and supplier
        share at least one common language in comments
        (string-based semantic join)
   --------------------------------------------------------- */
SELECT DISTINCT o.*
FROM orders o
JOIN customer c ON c.c_custkey = o.o_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
JOIN supplier s ON s.s_suppkey = l.l_suppkey
WHERE LOWER(c.c_comment) LIKE CONCAT('%', LOWER(s.s_name), '%')
   OR LOWER(s.s_comment) LIKE CONCAT('%', LOWER(c.c_name), '%');


/* ---------------------------------------------------------
   P46: Customer visible only if the variance of their
        order revenues is greater than zero
        (i.e., non-uniform spending behavior)
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
JOIN orders o ON o.o_custkey = c.c_custkey
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY c.c_custkey
HAVING COUNT(DISTINCT l.l_extendedprice * (1 - l.l_discount)) > 1;


/* ---------------------------------------------------------
   P47: Supplier visible only if they have never supplied
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
   P48: Lineitem visible only if its order date is closer
        to ship date than to receipt date
   --------------------------------------------------------- */
SELECT l.*
FROM lineitem l
JOIN orders o ON o.o_orderkey = l.l_orderkey
WHERE ABS(o.o_orderdate - l.l_shipdate)
    < ABS(o.o_orderdate - l.l_receiptdate);


/* ---------------------------------------------------------
   P49: Part visible only if it is supplied by suppliers
        from more than one nation
   --------------------------------------------------------- */
SELECT p.*
FROM part p
JOIN partsupp ps ON ps.ps_partkey = p.p_partkey
JOIN supplier s ON s.s_suppkey = ps.ps_suppkey
GROUP BY p.p_partkey
HAVING COUNT(DISTINCT s.s_nationkey) > 1;


/* ---------------------------------------------------------
   P50: Orders visible only if the average discount across
        its lineitems is strictly increasing with quantity
        (correlation-style policy)
   --------------------------------------------------------- */
SELECT o.*
FROM orders o
JOIN lineitem l ON l.l_orderkey = o.o_orderkey
GROUP BY o.o_orderkey
HAVING CORR(l.l_quantity, l.l_discount) > 0;

