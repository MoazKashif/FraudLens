-- 04_dw_ddl.sql  -  DATA WAREHOUSE SCHEMA (star schema from Phase 1)
-- Every dimension has a SURROGATE KEY (integer, generated) and keeps the BUSINESS KEY as a unique natural key.
SET search_path TO project_dw;

DROP TABLE IF EXISTS fact_customer_merchant, fact_daily_fraud_snapshot, fact_transactions CASCADE;
DROP TABLE IF EXISTS dim_date, dim_time, dim_customer, dim_merchant, dim_transactiontype, dim_behaviorrisk CASCADE;
DROP TABLE IF EXISTS etl_audit_log, dq_results CASCADE;

-- ===================== DIMENSIONS =====================
CREATE TABLE dim_date (
    date_key      INTEGER  PRIMARY KEY,                -- yyyymmdd surrogate key
    full_date     DATE     NOT NULL UNIQUE,            -- natural key
    day_of_month  SMALLINT NOT NULL,
    day_name      VARCHAR(9) NOT NULL,
    week_of_year  SMALLINT NOT NULL,
    month_number  SMALLINT NOT NULL,
    month_name    VARCHAR(9) NOT NULL,
    quarter       SMALLINT NOT NULL,
    year          SMALLINT NOT NULL,
    is_weekend    BOOLEAN  NOT NULL);

CREATE TABLE dim_time (
    time_key      SMALLINT PRIMARY KEY,                -- = hour 0..23
    hour_of_day   SMALLINT NOT NULL UNIQUE CHECK (hour_of_day BETWEEN 0 AND 23),
    hour_label    VARCHAR(11) NOT NULL,
    day_part      VARCHAR(10) NOT NULL);

CREATE TABLE dim_customer (
    customer_key      INTEGER GENERATED ALWAYS AS IDENTITY (START WITH 1001) PRIMARY KEY,   -- surrogate key
    customer_email    VARCHAR(100) NOT NULL UNIQUE,                                          -- business (natural) key
    customer_name     VARCHAR(100) NOT NULL,
    device_type       VARCHAR(10)  NOT NULL,
    card_expiry_month SMALLINT CHECK (card_expiry_month BETWEEN 1 AND 12),
    card_expiry_year  SMALLINT);

CREATE TABLE dim_merchant (
    merchant_key   INTEGER GENERATED ALWAYS AS IDENTITY (START WITH 5001) PRIMARY KEY,       -- surrogate key
    merchant_email VARCHAR(100) NOT NULL UNIQUE,                                             -- business (natural) key
    merchant_name  VARCHAR(100) NOT NULL);

CREATE TABLE dim_transactiontype (
    type_key        SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    type_name       VARCHAR(12) NOT NULL,
    money_direction VARCHAR(10) NOT NULL,
    location_region VARCHAR(15) NOT NULL,
    ip_prefix       VARCHAR(10) NOT NULL,
    UNIQUE (type_name, location_region, ip_prefix));

CREATE TABLE dim_behaviorrisk (
    behavior_key          SMALLINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    purchase_pattern      VARCHAR(12) NOT NULL,
    anomaly_level         VARCHAR(14) NOT NULL,
    login_frequency_band  VARCHAR(8)  NOT NULL,
    session_duration_band VARCHAR(8)  NOT NULL,
    UNIQUE (purchase_pattern, anomaly_level, login_frequency_band, session_duration_band));

-- ===================== FACTS =====================
CREATE TABLE fact_transactions (
    transaction_key  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key         INTEGER  NOT NULL REFERENCES dim_date(date_key),
    time_key         SMALLINT NOT NULL REFERENCES dim_time(time_key),
    customer_key     INTEGER  NOT NULL REFERENCES dim_customer(customer_key),
    merchant_key     INTEGER  NOT NULL REFERENCES dim_merchant(merchant_key),
    type_key         SMALLINT NOT NULL REFERENCES dim_transactiontype(type_key),
    behavior_key     SMALLINT NOT NULL REFERENCES dim_behaviorrisk(behavior_key),
    sender_account   VARCHAR(20) NOT NULL,             -- degenerate dimension
    receiver_account VARCHAR(20) NOT NULL,             -- degenerate dimension
    txn_timestamp    TIMESTAMP   NOT NULL,             -- degenerate
    txn_count        SMALLINT    NOT NULL DEFAULT 1,
    amount           NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    is_fraud         SMALLINT    NOT NULL CHECK (is_fraud IN (0,1)),
    fraud_amount     NUMERIC(12,2) NOT NULL,
    risk_score       NUMERIC(5,2)  NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    login_frequency  SMALLINT    NOT NULL,
    session_duration NUMERIC(10,2) NOT NULL,
    etl_batch_id     INTEGER     NOT NULL,
    load_timestamp   TIMESTAMP   NOT NULL DEFAULT now());

CREATE TABLE fact_daily_fraud_snapshot (
    date_key            INTEGER  NOT NULL REFERENCES dim_date(date_key),
    type_key            SMALLINT NOT NULL REFERENCES dim_transactiontype(type_key),
    txn_count           INTEGER  NOT NULL,
    fraud_txn_count     INTEGER  NOT NULL,
    high_risk_txn_count INTEGER  NOT NULL,
    total_amount        NUMERIC(14,2) NOT NULL,
    fraud_amount        NUMERIC(14,2) NOT NULL,
    fraud_rate          NUMERIC(6,4)  NOT NULL,
    avg_risk_score      NUMERIC(5,2)  NOT NULL,
    PRIMARY KEY (date_key, type_key));

CREATE TABLE fact_customer_merchant (                  -- factless fact
    customer_key INTEGER NOT NULL REFERENCES dim_customer(customer_key),
    merchant_key INTEGER NOT NULL REFERENCES dim_merchant(merchant_key),
    PRIMARY KEY (customer_key, merchant_key));

-- ===================== CONTROL TABLES =====================
CREATE TABLE etl_audit_log (
    log_id        SERIAL PRIMARY KEY,
    batch_id      INTEGER NOT NULL,
    step_name     TEXT    NOT NULL,
    status        TEXT    NOT NULL,                    -- SUCCESS / FAILED
    rows_processed BIGINT,
    started_at    TIMESTAMP NOT NULL,
    finished_at   TIMESTAMP,
    message       TEXT);

CREATE TABLE dq_results (
    check_id      SERIAL PRIMARY KEY,
    batch_id      INTEGER,
    check_group   TEXT NOT NULL,                       -- Completeness / Accuracy / Integrity
    check_name    TEXT NOT NULL,
    expected      NUMERIC,
    actual        NUMERIC,
    status        TEXT NOT NULL,                       -- PASS / FAIL
    details       TEXT,
    checked_at    TIMESTAMP NOT NULL DEFAULT now());
