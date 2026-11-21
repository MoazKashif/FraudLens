-- Physical model (PostgreSQL) generated from the Phase 1 design
CREATE SCHEMA IF NOT EXISTS dw;
SET search_path TO dw;

-- Calendar dimension at day grain, built from the transaction timestamps (all of 2022).
CREATE TABLE dim_date (
    date_key INTEGER PRIMARY KEY,
    full_date DATE NOT NULL,
    day_of_month SMALLINT NOT NULL,
    day_name VARCHAR(9) NOT NULL,
    week_of_year SMALLINT NOT NULL,
    month_number SMALLINT NOT NULL,
    month_name VARCHAR(9) NOT NULL,
    quarter SMALLINT NOT NULL,
    year SMALLINT NOT NULL,
    is_weekend BOOLEAN NOT NULL
);

-- Time-of-day dimension at hour grain, so time-of-day questions do not need a timestamp scan.
CREATE TABLE dim_time (
    time_key SMALLINT PRIMARY KEY,
    hour_of_day SMALLINT NOT NULL,
    hour_label VARCHAR(11) NOT NULL,
    day_part VARCHAR(10) NOT NULL
);

-- Customers from user.csv, with their device and card expiry. One row per distinct customer email.
CREATE TABLE dim_customer (
    customer_key INTEGER PRIMARY KEY,
    customer_email VARCHAR(100) NOT NULL,
    customer_name VARCHAR(100) NOT NULL,
    device_type VARCHAR(10) NOT NULL,
    card_expiry_month SMALLINT NOT NULL,
    card_expiry_year SMALLINT NOT NULL
);

-- Merchants from user.csv. One row per distinct merchant email.
CREATE TABLE dim_merchant (
    merchant_key INTEGER PRIMARY KEY,
    merchant_email VARCHAR(100) NOT NULL,
    merchant_name VARCHAR(100) NOT NULL
);

-- Transaction context from transaction_type.csv: the type plus the region and IP prefix it came from.
CREATE TABLE dim_transactiontype (
    type_key SMALLINT PRIMARY KEY,
    type_name VARCHAR(12) NOT NULL,
    money_direction VARCHAR(10) NOT NULL,
    location_region VARCHAR(15) NOT NULL,
    ip_prefix VARCHAR(10) NOT NULL
);

-- Mini-dimension of banded behaviour and risk attributes from behavior_risk.csv. The exact numbers stay in the fact as measures.
CREATE TABLE dim_behaviorrisk (
    behavior_key SMALLINT PRIMARY KEY,
    purchase_pattern VARCHAR(12) NOT NULL,
    anomaly_level VARCHAR(14) NOT NULL,
    login_frequency_band VARCHAR(8) NOT NULL,
    session_duration_band VARCHAR(8) NOT NULL
);

-- Core transaction fact. Transaction-grain, atomic.
CREATE TABLE fact_transactions (
    transaction_key BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    date_key INTEGER NOT NULL,
    time_key SMALLINT NOT NULL,
    customer_key INTEGER NOT NULL,
    merchant_key INTEGER NOT NULL,
    type_key SMALLINT NOT NULL,
    behavior_key SMALLINT NOT NULL,
    sender_account VARCHAR(20) NOT NULL,
    receiver_account VARCHAR(20) NOT NULL,
    txn_timestamp TIMESTAMP NOT NULL,
    txn_count SMALLINT NOT NULL,
    amount NUMERIC(12,2) NOT NULL,
    is_fraud SMALLINT NOT NULL,
    fraud_amount NUMERIC(12,2) NOT NULL,
    risk_score NUMERIC(5,2) NOT NULL,
    login_frequency SMALLINT NOT NULL,
    session_duration NUMERIC(10,2) NOT NULL,
    etl_batch_id INTEGER NOT NULL,
    load_timestamp TIMESTAMP NOT NULL,
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (time_key) REFERENCES dim_time(time_key),
    FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),
    FOREIGN KEY (merchant_key) REFERENCES dim_merchant(merchant_key),
    FOREIGN KEY (type_key) REFERENCES dim_transactiontype(type_key),
    FOREIGN KEY (behavior_key) REFERENCES dim_behaviorrisk(behavior_key)
);

-- Periodic snapshot fact. Daily fraud summary per transaction context, built by the ETL from Fact_Transactions for fast trend dashboards.
CREATE TABLE fact_daily_fraud_snapshot (
    date_key INTEGER NOT NULL,
    type_key SMALLINT NOT NULL,
    txn_count INTEGER NOT NULL,
    fraud_txn_count INTEGER NOT NULL,
    high_risk_txn_count INTEGER NOT NULL,
    total_amount NUMERIC(14,2) NOT NULL,
    fraud_amount NUMERIC(14,2) NOT NULL,
    fraud_rate NUMERIC(6,4) NOT NULL,
    avg_risk_score NUMERIC(5,2) NOT NULL,
    PRIMARY KEY (date_key, type_key),
    FOREIGN KEY (date_key) REFERENCES dim_date(date_key),
    FOREIGN KEY (type_key) REFERENCES dim_transactiontype(type_key)
);

-- Factless fact recording which customer is linked to which merchant (one record per row of user.csv). No measures.
CREATE TABLE fact_customer_merchant (
    customer_key INTEGER NOT NULL,
    merchant_key INTEGER NOT NULL,
    PRIMARY KEY (customer_key, merchant_key),
    FOREIGN KEY (customer_key) REFERENCES dim_customer(customer_key),
    FOREIGN KEY (merchant_key) REFERENCES dim_merchant(merchant_key)
);

-- Helpful indexes on the large fact
CREATE INDEX ix_fact_txn_datetime ON fact_transaction(datetime_key);
CREATE INDEX ix_fact_txn_sender ON fact_transaction(sender_key);
CREATE INDEX ix_fact_txn_receiver ON fact_transaction(receiver_key);
CREATE INDEX ix_fact_txn_type ON fact_transaction(type_key);
CREATE INDEX ix_fact_txn_flag ON fact_transaction(flag_key);
