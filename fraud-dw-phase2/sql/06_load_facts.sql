-- 06_load_facts.sql  -  FACT LOAD with BUSINESS KEY -> SURROGATE KEY mapping
-- Each business key in staging (email, date, hour, type/region/IP, behaviour bands) is looked up in its dimension
-- and replaced by the surrogate key before it is stored in the fact table.
--
-- Linking rule A1 (the four source files share no key): accounts row n is linked, deterministically, to
--   transaction context  ((n-1) mod N_T) + 1   and   user record  ((n-1) mod N_U) + 1
-- where N_T = rows in stg_transaction_type and N_U = rows in stg_user. The behaviour row has the same number
-- as the transaction context row. No RANDOM() is used, so every load gives the same result.
SET search_path TO project_dw, project_staging;

-- batch id is passed by the pipeline:  SELECT set_config('etl.batch_id', '1', false);
-- ---------- fact_transactions ----------
INSERT INTO fact_transactions
      (date_key, time_key, customer_key, merchant_key, type_key, behavior_key,
       sender_account, receiver_account, txn_timestamp, txn_count, amount, is_fraud, fraud_amount,
       risk_score, login_frequency, session_duration, etl_batch_id)
SELECT d.date_key, tm.time_key, c.customer_key, m.merchant_key, ty.type_key, b.behavior_key,
       a.sender_account, a.receiver_account, tt.txn_timestamp, 1, a.amount, a.is_fraud, a.amount * a.is_fraud,
       br.risk_score, br.login_frequency, br.session_duration,
       COALESCE(NULLIF(current_setting('etl.batch_id', true), ''), '1')::INTEGER
FROM stg_accounts a
CROSS JOIN (SELECT COUNT(*) AS n_t FROM stg_transaction_type) k1
CROSS JOIN (SELECT COUNT(*) AS n_u FROM stg_user) k2
LEFT JOIN stg_transaction_type tt ON tt.transaction_id = ((a.txn_seq - 1) % k1.n_t) + 1
LEFT JOIN stg_behavior_risk   br ON br.row_id          = tt.transaction_id
LEFT JOIN stg_user            u  ON u.row_id           = ((a.txn_seq - 1) % k2.n_u) + 1
-- business key -> surrogate key lookups
LEFT JOIN dim_customer        c  ON c.customer_email   = u.customer_email
LEFT JOIN dim_merchant        m  ON m.merchant_email   = u.merchant_email
LEFT JOIN dim_date            d  ON d.full_date        = tt.txn_timestamp::DATE
LEFT JOIN dim_time            tm ON tm.hour_of_day     = EXTRACT(HOUR FROM tt.txn_timestamp)::INT
LEFT JOIN dim_transactiontype ty ON ty.type_name = tt.type_name AND ty.location_region = tt.location_region AND ty.ip_prefix = tt.ip_prefix
LEFT JOIN dim_behaviorrisk    b  ON b.purchase_pattern = br.purchase_pattern AND b.anomaly_level = br.anomaly_level
                                AND b.login_frequency_band = br.login_frequency_band AND b.session_duration_band = br.session_duration_band
ORDER BY a.txn_seq;
-- A missing lookup leaves a NULL key and the NOT NULL constraint stops the load: no row is silently dropped.

-- indexes on the foreign keys (built after the bulk load for speed)
CREATE INDEX IF NOT EXISTS ix_ft_date     ON fact_transactions (date_key);
CREATE INDEX IF NOT EXISTS ix_ft_time     ON fact_transactions (time_key);
CREATE INDEX IF NOT EXISTS ix_ft_customer ON fact_transactions (customer_key);
CREATE INDEX IF NOT EXISTS ix_ft_merchant ON fact_transactions (merchant_key);
CREATE INDEX IF NOT EXISTS ix_ft_type     ON fact_transactions (type_key);
CREATE INDEX IF NOT EXISTS ix_ft_behavior ON fact_transactions (behavior_key);
CREATE INDEX IF NOT EXISTS ix_ft_sender   ON fact_transactions (sender_account);
CREATE INDEX IF NOT EXISTS ix_ft_fraud    ON fact_transactions (is_fraud) WHERE is_fraud = 1;
ANALYZE fact_transactions;

-- ---------- fact_daily_fraud_snapshot (periodic snapshot built from the transaction fact) ----------
INSERT INTO fact_daily_fraud_snapshot
      (date_key, type_key, txn_count, fraud_txn_count, high_risk_txn_count, total_amount, fraud_amount, fraud_rate, avg_risk_score)
SELECT f.date_key, f.type_key, COUNT(*), SUM(f.is_fraud),
       COUNT(*) FILTER (WHERE b.anomaly_level = 'High Risk'),
       SUM(f.amount), SUM(f.fraud_amount),
       ROUND(SUM(f.is_fraud)::NUMERIC / COUNT(*), 4), ROUND(AVG(f.risk_score), 2)
FROM fact_transactions f
JOIN dim_behaviorrisk b ON b.behavior_key = f.behavior_key
GROUP BY f.date_key, f.type_key;

-- ---------- fact_customer_merchant (factless: one row per customer-merchant link) ----------
INSERT INTO fact_customer_merchant (customer_key, merchant_key)
SELECT DISTINCT c.customer_key, m.merchant_key
FROM stg_user u
JOIN dim_customer c ON c.customer_email = u.customer_email
JOIN dim_merchant m ON m.merchant_email = u.merchant_email;

ANALYZE fact_daily_fraud_snapshot; ANALYZE fact_customer_merchant;
