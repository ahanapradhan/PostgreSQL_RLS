/* ---------------------------------------------------------
P5b:   Customer visible only if ALL orders in last year
       were HIGH priority
   --------------------------------------------------------- */
SELECT c.*
FROM customer c
WHERE EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.o_custkey = c.c_custkey
      AND o.o_orderdate >= DATE '1997-01-01'
)
AND NOT EXISTS (
    SELECT 1
    FROM orders o
    WHERE o.o_custkey = c.c_custkey
      AND o.o_orderdate >= DATE '1997-01-01'
      AND o.o_orderpriority <> '1-URGENT'
);

/* ---------------------------------------------------------
Customer and supplier who have the same comments
   --------------------------------------------------------- */
SELECT s.*
FROM customer c, supplier s
     WHERE c.c_comment LIKE '%' || s.s_comment || '%'   
AND c.c_acctbal > 0
  AND s.s_acctbal > 0;


/*
on lineitem 
*/
SELECT l.*
FROM lineitem l, partsupp ps, part p
     WHERE ps.ps_partkey = l.l_partkey
    AND ps.ps_suppkey = l.l_suppkey
     AND p.p_partkey = l.l_partkey
AND ps.ps_supplycost BETWEEN p.p_retailprice * 0.5
                           AND p.p_retailprice * 1.2;


/* on partsupp */
SELECT ps.*
FROM partsupp ps
WHERE NOT EXISTS (
    SELECT 1
    FROM lineitem l
    WHERE l.l_partkey = ps.ps_partkey
      AND l.l_extendedprice 
          < ps.ps_supplycost * l.l_quantity   
);
