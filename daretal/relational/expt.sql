-- =====================================================
-- CLEAN SETUP
-- =====================================================
reset role;
DROP TABLE IF EXISTS timing_runs CASCADE;
DROP TABLE IF EXISTS timing_summary CASCADE;
DROP VIEW IF EXISTS store_sales_view CASCADE;

DROP TABLE IF EXISTS store_sales CASCADE;
DROP TABLE IF EXISTS all_store_sales CASCADE;

DROP TABLE IF EXISTS store CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS customer_address CASCADE;

-- =====================================================
-- BASE TABLES (NO REFERENTIAL CONSTRAINTS)
-- =====================================================

CREATE TABLE customer_address (
    ca_address_sk INT PRIMARY KEY,
    ca_state      TEXT
);

CREATE TABLE customer (
    c_customer_sk     INT PRIMARY KEY,
    c_current_addr_sk INT
);

CREATE TABLE store (
    s_store_sk   INT PRIMARY KEY,
    s_address_sk INT
);

CREATE TABLE store_sales (
    ss_sold_date   DATE,
    ss_customer_sk INT,
    ss_store_sk    INT,
    ss_net_paid    NUMERIC
);

-- =====================================================
-- DATA GENERATION
-- =====================================================

-- 1,000 addresses across 10 states
INSERT INTO customer_address
SELECT g,
       'STATE_' || ((g % 10) + 1)
FROM generate_series(1,1000) g;

-- 100,000 customers assigned random addresses
INSERT INTO customer
SELECT g,
       (random()*999 + 1)::INT
FROM generate_series(1,100000) g;

-- 100 stores assigned random addresses
INSERT INTO store
SELECT g,
       (random()*999 + 1)::INT
FROM generate_series(1,100) g;

-- 300,000 sales
INSERT INTO store_sales
SELECT CURRENT_DATE,
       (random()*99999 + 1)::INT,
       (random()*99 + 1)::INT,
       (random()*200000)::NUMERIC
FROM generate_series(1,300000);

create table all_store_sales as select * from store_sales;

create view store_sales_view as 
SELECT ss.*
FROM store_sales ss
JOIN customer c
ON ss.ss_customer_sk = c.c_customer_sk
JOIN customer_address ca
ON c.c_current_addr_sk = ca.ca_address_sk
JOIN store s
ON ss.ss_store_sk = s.s_store_sk
JOIN customer_address sa
ON s.s_address_sk = sa.ca_address_sk
 WHERE ca.ca_state = sa.ca_state;
-- =====================================================
-- OPTIMAL INDEXES FOR THE QUERY
-- =====================================================

-- store_sales join lookups
CREATE INDEX idx_ss_customer
ON store_sales (ss_customer_sk);

CREATE INDEX idx_ss_store
ON store_sales (ss_store_sk);

-- store_sales join lookups
CREATE INDEX idx_all_ss_customer
ON all_store_sales (ss_customer_sk);

CREATE INDEX idx_all_ss_store
ON all_store_sales (ss_store_sk);

-- customer join
CREATE INDEX idx_customer_addr
ON customer (c_customer_sk, c_current_addr_sk);

-- store join
CREATE INDEX idx_store_addr
ON store (s_store_sk, s_address_sk);

-- address lookup and state comparison
CREATE INDEX idx_address_state
ON customer_address (ca_address_sk, ca_state);

ANALYZE;


ALTER TABLE store_sales ENABLE ROW LEVEL SECURITY;

CREATE POLICY sales_same_state_policy
ON store_sales
FOR SELECT
USING (
    EXISTS (
        SELECT 1
        FROM customer c
        JOIN customer_address ca
          ON c.c_current_addr_sk = ca.ca_address_sk
        JOIN store s
          ON store_sales.ss_store_sk = s.s_store_sk
        JOIN customer_address sa
          ON s.s_address_sk = sa.ca_address_sk
        WHERE c.c_customer_sk = store_sales.ss_customer_sk
          AND ca.ca_state = sa.ca_state
    )
);

GRANT SELECT ON store_sales TO rls_user;
GRANT SELECT ON all_store_sales TO rls_user;
GRANT SELECT ON store_sales_view TO rls_user;

GRANT SELECT ON customer TO rls_user;
GRANT SELECT ON store TO rls_user;
GRANT SELECT ON customer_address TO rls_user;

CREATE TABLE timing_runs (
    attack_name TEXT,
    run_no INT,
    exec_ms NUMERIC
);

CREATE TABLE timing_summary (
    attack_name TEXT,
    avg_ms NUMERIC
);

GRANT ALL ON timing_runs TO rls_user;
GRANT ALL ON timing_summary TO rls_user;

CREATE OR REPLACE FUNCTION record_timing(
    attack TEXT,
    run_id INT,
    sql_query TEXT
)
RETURNS VOID AS $$
DECLARE
    t1 TIMESTAMP;
    t2 TIMESTAMP;
BEGIN
    t1 := clock_timestamp();
    EXECUTE sql_query;
    t2 := clock_timestamp();

    INSERT INTO timing_runs
    VALUES (
        attack,
        run_id,
        EXTRACT(EPOCH FROM (t2 - t1)) * 1000
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- baseline

CREATE OR REPLACE FUNCTION probe_baseline_without_rls(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'scan_without_rls',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM all_store_sales c
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_baseline(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'scan',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM store_sales c
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_baseline_view(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'scan_view',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM store_sales_view c
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- join-filter

CREATE OR REPLACE FUNCTION probe_amplification(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'join-filter',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
        JOIN store_sales ss
          ON c.c_customer_sk = ss.ss_customer_sk
        WHERE ss.ss_net_paid < 1500
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_amplification_view(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'join-filter_view',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
        JOIN store_sales_view ss
          ON c.c_customer_sk = ss.ss_customer_sk
        WHERE ss.ss_net_paid < 1500
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_amplification_without_rls(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'join-filter_without_rls',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
        JOIN all_store_sales ss
          ON c.c_customer_sk = ss.ss_customer_sk
        WHERE ss.ss_net_paid < 1500
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- agg/group

CREATE OR REPLACE FUNCTION probe_group_collapse(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'group_agg',
        run_id,
        $q$
        SELECT c.ss_store_sk, COUNT(*)
        FROM store_sales c
        GROUP BY c.ss_store_sk
        HAVING COUNT(*) > 0
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_group_collapse_view(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'group_agg_view',
        run_id,
        $q$
        SELECT c.ss_store_sk, COUNT(*)
        FROM store_sales_view c
        GROUP BY c.ss_store_sk
        HAVING COUNT(*) > 0
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_group_collapse_without_rls(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'group_agg_without_rls',
        run_id,
        $q$
        SELECT c.ss_store_sk, COUNT(*)
        FROM all_store_sales c
        GROUP BY c.ss_store_sk
        HAVING COUNT(*) > 0
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

-- sort

CREATE OR REPLACE FUNCTION probe_order_by(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'order_by',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM store_sales c
        ORDER BY c.ss_store_sk
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_order_by_view(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'order_by_view',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM store_sales_view c
        ORDER BY c.ss_store_sk
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

CREATE OR REPLACE FUNCTION probe_order_by_without_rls(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'order_by_without_rls',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM all_store_sales c
        ORDER BY c.ss_store_sk
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

--- run each for 30 times

set role 'rls_user';
DO $$
DECLARE
    i INT;
BEGIN
    FOR i IN 1..30 LOOP
	    PERFORM probe_baseline_without_rls(i);
        PERFORM probe_baseline(i);
		        PERFORM probe_baseline_view(i);
        PERFORM probe_amplification(i);
        PERFORM probe_group_collapse(i);
        PERFORM probe_order_by(i);
		PERFORM probe_amplification_without_rls(i);
        PERFORM probe_group_collapse_without_rls(i);
        PERFORM probe_order_by_without_rls(i);
		PERFORM probe_amplification_view(i);
        PERFORM probe_group_collapse_view(i);
        PERFORM probe_order_by_view(i);
    END LOOP;
END;
$$;

------------------------------------------------------------
-- AGGREGATE RESULTS
------------------------------------------------------------

INSERT INTO timing_summary
(
SELECT attack_name,
       ROUND(AVG(exec_ms),4)
FROM timing_runs
GROUP BY attack_name
ORDER BY attack_name);

------------------------------------------------------------
-- VIEW RESULTS
------------------------------------------------------------
reset role;

SELECT * FROM timing_summary;
