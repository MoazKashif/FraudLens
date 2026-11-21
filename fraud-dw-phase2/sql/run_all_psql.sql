-- run_all_psql.sql  -  pure-SQL alternative to etl/etl_pipeline.py (uses psql meta-commands)
-- Run from the repository root:
--     psql -U postgres -d fraud_dw -f sql/run_all_psql.sql
-- (create the database first with sql/00_create_database.sql)
\set ON_ERROR_STOP on
SELECT set_config('etl.batch_id', '1', false);

\i sql/01_create_schemas.sql
\i sql/02_staging_ddl.sql

-- EXTRACT: client-side COPY of the four CSV files into the raw landing tables
\copy project_staging.raw_accounts (sender_account, receiver_account, amount, is_fraud) FROM 'data/accounts.csv' WITH (FORMAT csv, HEADER true)
\copy project_staging.raw_transaction_type (transaction_id, transaction_type, location_region, ip_prefix, txn_timestamp) FROM 'data/transaction_type.csv' WITH (FORMAT csv, HEADER true)
\copy project_staging.raw_behavior_risk (login_frequency, session_duration, purchase_pattern, risk_score, anomaly) FROM 'data/behavior_risk.csv' WITH (FORMAT csv, HEADER true)
\copy project_staging.raw_user (customer_name, customer_email, merchant_name, merchant_email, card_number, card_expiry, device_type) FROM 'data/user.csv' WITH (FORMAT csv, HEADER true)

-- TRANSFORM and LOAD
\i sql/03_staging_clean.sql
\i sql/04_dw_ddl.sql
\i sql/05_load_dimensions.sql
\i sql/06_load_facts.sql
\i sql/07_reporting_views.sql
\i sql/08_data_quality.sql

SELECT check_group, COUNT(*) FILTER (WHERE status = 'PASS') AS pass, COUNT(*) FILTER (WHERE status = 'FAIL') AS fail
FROM project_dw.dq_results GROUP BY 1 ORDER BY 1;
