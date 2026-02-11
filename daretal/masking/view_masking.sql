------------------------------------------------------------
-- CLEANUP
------------------------------------------------------------
reset role;

DROP TABLE IF EXISTS store_sales CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS all_customer CASCADE;
DROP TABLE IF EXISTS timing_runs CASCADE;
DROP TABLE IF EXISTS timing_summary CASCADE;
--DROP ROLE IF EXISTS rls_user;

-- Drop tables if they exist
DROP TABLE IF EXISTS store_sales;
DROP TABLE IF EXISTS customer;

-- 1. Create customer table
CREATE TABLE customer (
    c_customer_sk SERIAL PRIMARY KEY,
    c_first_name VARCHAR(50) NOT NULL
);

-- 2. Create store_sales table
CREATE TABLE store_sales (
    ss_ticket_number SERIAL PRIMARY KEY,
    ss_customer_sk INT REFERENCES customer(c_customer_sk),
    ss_quantity INT,
    ss_sales_price NUMERIC(10,2),
    ss_date DATE
);

-- 3. Insert 1000 random customers
INSERT INTO customer (c_first_name)
SELECT
    'Customer_' || trunc(random()*1000)::int
FROM generate_series(1, 1000);

-- 4. Insert 20000 random store_sales rows
INSERT INTO store_sales (ss_customer_sk, ss_quantity, ss_sales_price, ss_date)
SELECT
    (trunc(random()*1000)::int + 1),          -- random customer_sk from 1 to 1000
    (trunc(random()*10)::int + 1),           -- quantity 1-10
    round((random()*10000)::numeric, 2),       -- price 0.00 - 100.00
    CURRENT_DATE - (trunc(random()*365)::int) -- random date in past year
FROM generate_series(1, 20000);

create table all_customer as select * from customer;

CREATE VIEW customer_masked_view
WITH (security_barrier) AS
SELECT
    c.c_customer_sk,
    CASE
        WHEN COUNT(ss.ss_ticket_number) >= 3
        THEN c.c_first_name
        ELSE 'REDACTED'
    END AS c_first_name
FROM customer c
LEFT JOIN store_sales ss
    ON ss.ss_customer_sk = c.c_customer_sk
GROUP BY c.c_customer_sk, c.c_first_name;


------------------------------------------------------------
-- INDEXES (critical for optimizer behavior)
------------------------------------------------------------

CREATE INDEX idx_store_sales_customer_sk ON store_sales(ss_customer_sk);
CREATE INDEX idx_store_sales_customer_sk_ticket ON store_sales(ss_customer_sk, ss_ticket_number);
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
        WHERE ss_sales_price > 1000
    )
);

------------------------------------------------------------
-- CREATE RLS USER
------------------------------------------------------------

--CREATE ROLE rls_user LOGIN PASSWORD 'rls_pass';

--GRANT CONNECT ON DATABASE tpch TO rls_user;
--GRANT USAGE ON SCHEMA public TO rls_user;

GRANT SELECT ON store_sales TO rls_user;
GRANT SELECT ON all_customer TO rls_user;

REVOKE SELECT ON customer FROM rls_user;

-- Grant access to the masked view
GRANT SELECT ON customer_masked_view TO rls_user;

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
CREATE OR REPLACE FUNCTION without_rls(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'without_rls',
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
        FROM customer_masked_view c
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
        FROM customer_masked_view c
        JOIN store_sales ss
          ON c.c_customer_sk = ss.ss_customer_sk
        WHERE ss.ss_sales_price < 1500
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
        FROM customer_masked_view c
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
        FROM customer_masked_view c
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
            'SELECT * FROM customer_masked_view WHERE c_customer_sk = %s',
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
	    PERFORM without_rls(i);
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

--SELECT * FROM timing_summary;

WITH base_time as (select avg_ms from timing_summary where attack_name = 'without_rls')
select attack_name, ROUND(avg_ms/(SELECT avg_ms FROM base_time), 4) as rel_avg
from timing_summary
where attack_name <> 'without_rls';

