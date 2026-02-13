-- ============================================================
-- DROP TABLES IF THEY EXIST
-- ============================================================
reset role;
DROP TABLE IF EXISTS timing_runs CASCADE;
DROP TABLE IF EXISTS timing_summary CASCADE;
drop view if exists customer_view cascade;
DROP TABLE IF EXISTS all_customer CASCADE;
DROP TABLE IF EXISTS customer CASCADE;
DROP TABLE IF EXISTS customer_address CASCADE;

-- ============================================================
-- CREATE TABLES
-- ============================================================

CREATE TABLE customer_address (
    ca_address_sk     INT,
    ca_state          CHAR(2),
    ca_city           TEXT,
    ca_zip            TEXT
);

CREATE TABLE customer (
    c_customer_sk        INT,
    c_current_addr_sk    INT,
    c_current_balance    NUMERIC(12,2),
    c_first_name         TEXT,
    c_last_name          TEXT
);

-- ============================================================
-- DATA GENERATION
-- ============================================================

-- 100,000 addresses across 50 states
INSERT INTO customer_address
SELECT
    addr_id,
    (ARRAY[
        'CA','NY','TX','FL','IL','PA','OH','MI','GA','NC',
        'NJ','VA','WA','AZ','MA','TN','IN','MO','MD','WI',
        'CO','MN','SC','AL','LA','KY','OR','OK','CT','UT',
        'IA','NV','AR','MS','KS','NM','NE','WV','ID','HI',
        'NH','ME','MT','RI','DE','SD','ND','AK','VT','WY'
    ])[1 + (random()*49)::INT],
    'City_' || addr_id,
    LPAD((random()*99999)::INT::TEXT, 5, '0')
FROM generate_series(1,100000) AS addr_id;


-- 1,000,000 customers with random balances and addresses
INSERT INTO customer
SELECT
    cust_id,
    1 + (random()*99999)::INT,
    (random()*200000 - 50000)::NUMERIC(12,2),  -- range: -50k to +150k
    'First_' || cust_id,
    'Last_' || cust_id
FROM generate_series(1,1000000) AS cust_id;

create table all_customer as select * from customer;

-- ============================================================
-- OPTIMAL INDEXES FOR THIS QUERY
-- ============================================================

-- CRITICAL: speeds up join and state filtering
CREATE INDEX idx_ca_address_sk
ON customer_address(ca_address_sk);

-- CRITICAL: speeds up state lookup in correlated subquery
CREATE INDEX idx_ca_state_address
ON customer_address(ca_state, ca_address_sk);

-- CRITICAL: speeds up join from customer -> address
CREATE INDEX idx_customer_addr
ON customer(c_current_addr_sk);

-- MOST IMPORTANT INDEX:
-- supports AVG(balance) grouped by state efficiently
-- and supports balance comparison
CREATE INDEX idx_customer_addr_balance
ON customer(c_current_addr_sk, c_current_balance);

CREATE INDEX idx_all_customer_addr
ON all_customer(c_current_addr_sk);

-- MOST IMPORTANT INDEX:
-- supports AVG(balance) grouped by state efficiently
-- and supports balance comparison
CREATE INDEX idx_all_customer_addr_balance
ON all_customer(c_current_addr_sk, c_current_balance);

-- Optional but beneficial for large scans and comparisons
CREATE INDEX idx_customer_balance
ON customer(c_current_balance);

-- Optional but beneficial for large scans and comparisons
CREATE INDEX idx_all_customer_balance
ON all_customer(c_current_balance);
-- ============================================================
-- UPDATE STATISTICS
-- ============================================================

ANALYZE customer;
ANALYZE all_customer;
ANALYZE customer_address;


-- ============================================================
-- TEST QUERY (FAST EXECUTION VERSION)
-- ============================================================

create view customer_view as
SELECT c.*
FROM all_customer c
JOIN customer_address ca
  ON c.c_current_addr_sk = ca.ca_address_sk
WHERE c.c_current_balance >
  (
    SELECT AVG(c2.c_current_balance)
    FROM all_customer c2
    JOIN customer_address ca2
      ON c2.c_current_addr_sk = ca2.ca_address_sk
    WHERE ca2.ca_state = ca.ca_state
  );

ALTER TABLE customer ENABLE ROW LEVEL SECURITY;

-- Create the RLS policy
CREATE POLICY rls_customer_above_state_avg
ON customer
FOR SELECT
USING (
    c_current_balance >
    (
        SELECT AVG(c2.c_current_balance)
        FROM customer c2
        JOIN customer_address ca2
          ON c2.c_current_addr_sk = ca2.ca_address_sk
        WHERE ca2.ca_state =
        (
            SELECT ca1.ca_state
            FROM customer_address ca1
            WHERE ca1.ca_address_sk = customer.c_current_addr_sk
        )
    )
);


GRANT SELECT ON customer TO rls_user;
GRANT SELECT ON customer_address TO rls_user;

GRANT SELECT ON customer_view TO rls_user;

GRANT SELECT ON all_customer TO rls_user;


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



CREATE OR REPLACE FUNCTION probe_amplification_view(run_id INT)
RETURNS VOID AS $$
BEGIN
    PERFORM record_timing(
        'join-filter_view',
        run_id,
        $q$
        SELECT DISTINCT c.*
FROM customer_view c
JOIN customer_address ca
  ON c.c_current_addr_sk = ca.ca_address_sk
WHERE c.c_current_balance < 1500;
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
JOIN customer_address ca
  ON c.c_current_addr_sk = ca.ca_address_sk
WHERE c.c_current_balance < 1500;
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
        SELECT
    c_current_addr_sk,
    COUNT(*) AS num_customers
FROM customer_view
GROUP BY c_current_addr_sk
HAVING COUNT(*) >= 5;
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
        SELECT
    c_current_addr_sk,
    COUNT(*) AS num_customers
FROM all_customer
GROUP BY c_current_addr_sk
HAVING COUNT(*) >= 5;
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
        SELECT
     distinct c.*
FROM customer_view
ORDER BY c_current_balance DESC;
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
        SELECT
     distinct c.*
FROM all_customer
ORDER BY c_current_balance DESC;
        $q$
    );
END;
$$ LANGUAGE plpgsql SECURITY INVOKER;


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
