-- 02_staging_ddl.sql  -  STAGING SCHEMA
-- raw_*  : exact copy of the CSV files, every column TEXT, row_id keeps the file order.
-- stg_*  : cleaned, typed tables (filled by 03_staging_clean.sql).
SET search_path TO project_staging;

DROP TABLE IF EXISTS raw_accounts, raw_transaction_type, raw_behavior_risk, raw_user CASCADE;
DROP TABLE IF EXISTS stg_accounts, stg_transaction_type, stg_behavior_risk, stg_user, stg_customer, stg_merchant CASCADE;
DROP TABLE IF EXISTS rejected_rows, cleaning_log CASCADE;

-- ---------- raw (landing) tables ----------
CREATE TABLE raw_accounts (
    row_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    sender_account    TEXT, receiver_account TEXT, amount TEXT, is_fraud TEXT);
CREATE TABLE raw_transaction_type (
    row_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    transaction_id    TEXT, transaction_type TEXT, location_region TEXT, ip_prefix TEXT, txn_timestamp TEXT);
CREATE TABLE raw_behavior_risk (
    row_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    login_frequency   TEXT, session_duration TEXT, purchase_pattern TEXT, risk_score TEXT, anomaly TEXT);
CREATE TABLE raw_user (
    row_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_name TEXT, customer_email TEXT, merchant_name TEXT, merchant_email TEXT,
    card_number TEXT, card_expiry TEXT, device_type TEXT);

-- ---------- cleaned staging tables ----------
CREATE TABLE stg_accounts (
    txn_seq           BIGINT PRIMARY KEY,            -- 1..n in file order (used by linking rule A1)
    sender_account    VARCHAR(20)   NOT NULL,
    receiver_account  VARCHAR(20)   NOT NULL,
    amount            NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    is_fraud          SMALLINT      NOT NULL CHECK (is_fraud IN (0,1)));
CREATE TABLE stg_transaction_type (
    transaction_id    INTEGER PRIMARY KEY,           -- 1..37,417 (blank rows removed)
    type_name         VARCHAR(12)  NOT NULL,
    location_region   VARCHAR(15)  NOT NULL,
    ip_prefix         VARCHAR(10)  NOT NULL,
    txn_timestamp     TIMESTAMP    NOT NULL);
CREATE TABLE stg_behavior_risk (
    row_id            INTEGER PRIMARY KEY,
    login_frequency   SMALLINT      NOT NULL,
    session_duration  NUMERIC(10,2) NOT NULL,
    purchase_pattern  VARCHAR(12)   NOT NULL,
    risk_score        NUMERIC(5,2)  NOT NULL,
    anomaly_level     VARCHAR(14)   NOT NULL,
    login_frequency_band  VARCHAR(8) NOT NULL,
    session_duration_band VARCHAR(8) NOT NULL);
CREATE TABLE stg_user (                               -- all 2,000 customer-merchant records
    row_id            INTEGER PRIMARY KEY,
    customer_email    VARCHAR(100) NOT NULL,
    merchant_email    VARCHAR(100) NOT NULL);
CREATE TABLE stg_customer (                           -- de-duplicated customers
    customer_email    VARCHAR(100) PRIMARY KEY,
    customer_name     VARCHAR(100) NOT NULL,
    device_type       VARCHAR(10)  NOT NULL,
    card_expiry_month SMALLINT, card_expiry_year SMALLINT);
CREATE TABLE stg_merchant (                           -- de-duplicated merchants
    merchant_email    VARCHAR(100) PRIMARY KEY,
    merchant_name     VARCHAR(100) NOT NULL);

-- ---------- audit of cleaning ----------
CREATE TABLE rejected_rows (
    source_table TEXT, row_id BIGINT, reason TEXT, raw_data TEXT, rejected_at TIMESTAMP DEFAULT now());
CREATE TABLE cleaning_log (
    log_id SERIAL PRIMARY KEY, source_table TEXT, rule_name TEXT, rule_type TEXT,
    rows_before BIGINT, rows_after BIGINT, rows_affected BIGINT, note TEXT, logged_at TIMESTAMP DEFAULT now());
