------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------
reset role;



DROP TABLE IF EXISTS store_sales CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS all_customer CASCADE;
DROP TABLE IF EXISTS timing_runs CASCADE;
DROP TABLE IF EXISTS timing_summary CASCADE;
DROP VIEW IF EXISTS customer_view CASCADE;
--DROP ROLE IF EXISTS rls_user;

------------------------------------------------------------
-- BASE TABLES
------------------------------------------------------------

CREATE TABLE customer (
    c_customer_sk INT PRIMARY KEY,
    c_first_name  TEXT,
    c_last_name   TEXT
);

CREATE TABLE store_sales (
    ss_sold_date  DATE,
    ss_customer_sk INT,
	ss_store_sk     INT,
    ss_net_paid    NUMERIC
);

------------------------------------------------------------
-- DATA POPULATION
------------------------------------------------------------

-- 100000 customers
INSERT INTO customer
SELECT i, 'Name_'||i, 'Last_'||i
FROM generate_series(1,100000) AS s(i);

CREATE TABLE all_customer AS (SELECT * from customer);

CREATE VIEW customer_view AS
SELECT c.*
FROM customer c
JOIN store_sales ss
ON ss.ss_customer_sk = c.c_customer_sk
GROUP BY c.c_customer_sk
HAVING COUNT(DISTINCT ss.ss_store_sk) >= 3;



-- 200,0000 sales rows (random distribution)
INSERT INTO store_sales
SELECT CURRENT_DATE,
       (random()*99999 + 1)::INT,
	   (random()*49 + 1)::INT,
       (random()*200000)::NUMERIC
FROM generate_series(1,200000);

------------------------------------------------------------
-- INDEXES (critical for optimizer behavior)
------------------------------------------------------------

CREATE INDEX idx_sales_customer ON store_sales(ss_customer_sk);
CREATE INDEX idx_sales_paid ON store_sales(ss_net_paid);
CREATE INDEX idx_store_sales_customer_store ON store_sales (ss_customer_sk, ss_store_sk);

ANALYZE;

------------------------------------------------------------
-- ENABLE RLS
------------------------------------------------------------

ALTER TABLE customer ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_policy
ON customer
FOR SELECT
USING (
    (
        SELECT COUNT(DISTINCT ss.ss_store_sk)
        FROM store_sales ss
        WHERE ss.ss_customer_sk = customer.c_customer_sk
    ) >= 3
);



------------------------------------------------------------
-- CREATE RLS USER
------------------------------------------------------------

--CREATE ROLE rls_user LOGIN PASSWORD 'rls_pass';

--GRANT CONNECT ON DATABASE tpch TO rls_user;
--GRANT USAGE ON SCHEMA public TO rls_user;

GRANT SELECT ON customer TO rls_user;
GRANT SELECT ON store_sales TO rls_user;
GRANT SELECT ON all_customer TO rls_user;
GRANT SELECT ON customer_view TO rls_user;


------------------------------------------------------------
-- TIMING TABLES
------------------------------------------------------------

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

------------------------------------------------------------
-- GENERIC TIMER WRAPPER
------------------------------------------------------------

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

------------------------------------------------------------
-- PROBE DEFINITIONS
------------------------------------------------------------
------------------------------------------------------------
-- 0. BASELINE WITHOUT RLS
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_baseline_without_rls(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'scan_without_rls',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM all_customer c
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;


------------------------------------------------------------
-- 1. BASELINE
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_baseline(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'scan',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
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
        FROM customer_view c
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

------------------------------------------------------------
-- 2. AGGREGATION AMPLIFICATION
------------------------------------------------------------
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
        FROM customer_view c
        JOIN store_sales ss
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
        FROM all_customer c
        JOIN store_sales ss
          ON c.c_customer_sk = ss.ss_customer_sk
        WHERE ss.ss_net_paid < 1500
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

------------------------------------------------------------
-- 3. GROUP COLLAPSE
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_group_collapse(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'group_agg',
        run_id,
        $q$
        SELECT c.c_customer_sk, COUNT(*)
        FROM customer c
        GROUP BY c.c_customer_sk
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
        SELECT c.c_customer_sk, COUNT(*)
        FROM customer_view c
        GROUP BY c.c_customer_sk
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
        SELECT c.c_customer_sk, COUNT(*)
        FROM all_customer c
        GROUP BY c.c_customer_sk
        HAVING COUNT(*) > 0
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

------------------------------------------------------------
-- 4. ORDER BY LEAK
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_order_by(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'order_by',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
        ORDER BY c.c_customer_sk
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
        FROM customer_view c
        ORDER BY c.c_customer_sk
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
        FROM all_customer c
        ORDER BY c.c_customer_sk
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;

------------------------------------------------------------
-- 5. PER-CUSTOMER ORACLE
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_per_customer(run_id INT, cust INT)
RETURNS VOID AS $$
DECLARE
    attack_label TEXT;
BEGIN
    attack_label := 'per_customer_oracle (' || cust || ')';

    PERFORM record_timing(
        attack_label,
        run_id,
        format(
            'SELECT * FROM customer WHERE c_customer_sk = %s',
            cust
        )
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;


------------------------------------------------------------
-- EXECUTE ALL PROBES 30 TIMES
------------------------------------------------------------
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

       -- PERFORM probe_per_customer(i,1);
      --  PERFORM probe_per_customer(i,2);
      --  PERFORM probe_per_customer(i,3);
      --  PERFORM probe_per_customer(i,4);
      --  PERFORM probe_per_customer(i,5);
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


