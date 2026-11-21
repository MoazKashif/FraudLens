-- 08_data_quality.sql  -  DATA QUALITY VALIDATION
-- Completeness (missing values), Accuracy (reconciliation) and Integrity (foreign keys).
-- Each check stores expected vs actual in project_dw.dq_results; status is PASS when they agree.
SET search_path TO project_dw, project_staging;

CREATE OR REPLACE FUNCTION project_dw.dq_record(p_group TEXT, p_name TEXT, p_expected NUMERIC, p_actual NUMERIC,
                                                p_op TEXT DEFAULT '=', p_details TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    INSERT INTO project_dw.dq_results (batch_id, check_group, check_name, expected, actual, status, details)
    VALUES (COALESCE(NULLIF(current_setting('etl.batch_id', true), ''), '1')::INT, p_group,
            p_name, p_expected, p_actual,
            CASE WHEN (p_op = '=' AND p_actual = p_expected) OR (p_op = '>=' AND p_actual >= p_expected) THEN 'PASS' ELSE 'FAIL' END,
            COALESCE(p_details, CASE p_op WHEN '=' THEN 'actual must equal expected' ELSE 'actual must be >= expected' END));
END $$;

TRUNCATE project_dw.dq_results RESTART IDENTITY;

-- =============================== COMPLETENESS ===============================
SELECT dq_record('Completeness','Source rows accounted for: accounts.csv (raw = staged + rejected)',
       (SELECT COUNT(*) FROM raw_accounts), (SELECT COUNT(*) FROM stg_accounts) + (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_accounts'));
SELECT dq_record('Completeness','Source rows accounted for: transaction_type.csv (raw = staged + rejected)',
       (SELECT COUNT(*) FROM raw_transaction_type), (SELECT COUNT(*) FROM stg_transaction_type) + (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_transaction_type'));
SELECT dq_record('Completeness','Source rows accounted for: behavior_risk.csv (raw = staged + rejected)',
       (SELECT COUNT(*) FROM raw_behavior_risk), (SELECT COUNT(*) FROM stg_behavior_risk) + (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_behavior_risk'));
SELECT dq_record('Completeness','Source rows accounted for: user.csv (raw = staged + rejected)',
       (SELECT COUNT(*) FROM raw_user), (SELECT COUNT(*) FROM stg_user) + (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_user'));
SELECT dq_record('Completeness','Every staged transaction reached the fact table (row count)',
       (SELECT COUNT(*) FROM stg_accounts), (SELECT COUNT(*) FROM fact_transactions));
SELECT dq_record('Completeness','Fact rows with a NULL in any column',
       0, (SELECT COUNT(*) FROM fact_transactions f WHERE f.date_key IS NULL OR f.time_key IS NULL OR f.customer_key IS NULL OR f.merchant_key IS NULL
            OR f.type_key IS NULL OR f.behavior_key IS NULL OR f.sender_account IS NULL OR f.receiver_account IS NULL OR f.txn_timestamp IS NULL
            OR f.amount IS NULL OR f.is_fraud IS NULL OR f.fraud_amount IS NULL OR f.risk_score IS NULL OR f.login_frequency IS NULL OR f.session_duration IS NULL));
SELECT dq_record('Completeness','Staged accounts with empty sender or receiver',
       0, (SELECT COUNT(*) FROM stg_accounts WHERE TRIM(sender_account) = '' OR TRIM(receiver_account) = ''));
SELECT dq_record('Completeness','Customers with NULL or empty business key / name in dim_customer',
       0, (SELECT COUNT(*) FROM dim_customer WHERE TRIM(customer_email) = '' OR TRIM(customer_name) = ''));
SELECT dq_record('Completeness','Merchants with NULL or empty business key / name in dim_merchant',
       0, (SELECT COUNT(*) FROM dim_merchant WHERE TRIM(merchant_email) = '' OR TRIM(merchant_name) = ''));
SELECT dq_record('Completeness','Staged customers loaded into dim_customer',
       (SELECT COUNT(*) FROM stg_customer), (SELECT COUNT(*) FROM dim_customer));
SELECT dq_record('Completeness','Staged merchants loaded into dim_merchant',
       (SELECT COUNT(*) FROM stg_merchant), (SELECT COUNT(*) FROM dim_merchant));
SELECT dq_record('Completeness','Distinct customer-merchant pairs loaded into fact_customer_merchant',
       (SELECT COUNT(*) FROM (SELECT DISTINCT customer_email, merchant_email FROM stg_user) x), (SELECT COUNT(*) FROM fact_customer_merchant));
SELECT dq_record('Completeness','Minimum size: fact records >= 10,000', 10000, (SELECT COUNT(*) FROM fact_transactions), '>=');
SELECT dq_record('Completeness','Minimum size: dimension records >= 100 (all dimensions together)', 100,
       (SELECT (SELECT COUNT(*) FROM dim_date) + (SELECT COUNT(*) FROM dim_time) + (SELECT COUNT(*) FROM dim_customer) + (SELECT COUNT(*) FROM dim_merchant)
              + (SELECT COUNT(*) FROM dim_transactiontype) + (SELECT COUNT(*) FROM dim_behaviorrisk)), '>=');
SELECT dq_record('Completeness','Minimum size: dim_customer >= 100', 100, (SELECT COUNT(*) FROM dim_customer), '>=');
SELECT dq_record('Completeness','Minimum size: dim_merchant >= 100', 100, (SELECT COUNT(*) FROM dim_merchant), '>=');
SELECT dq_record('Completeness','Every transaction context has a behaviour row (staging)',
       0, (SELECT COUNT(*) FROM stg_transaction_type t LEFT JOIN stg_behavior_risk b ON b.row_id = t.transaction_id WHERE b.row_id IS NULL));

-- =============================== ACCURACY ===============================
SELECT dq_record('Accuracy','Revenue reconciliation: SUM(amount) source file vs fact table',
       (SELECT SUM(amount::NUMERIC) FROM raw_accounts r WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table='raw_accounts' AND x.row_id=r.row_id)),
       (SELECT SUM(amount) FROM fact_transactions));
SELECT dq_record('Accuracy','Fraud count reconciliation: TRUE in source file vs SUM(is_fraud) in fact',
       (SELECT COUNT(*) FROM raw_accounts WHERE UPPER(TRIM(is_fraud)) = 'TRUE'), (SELECT SUM(is_fraud) FROM fact_transactions));
SELECT dq_record('Accuracy','Fraud loss reconciliation: SUM(amount) of fraud rows in source vs SUM(fraud_amount)',
       (SELECT SUM(amount::NUMERIC) FROM raw_accounts WHERE UPPER(TRIM(is_fraud)) = 'TRUE'), (SELECT SUM(fraud_amount) FROM fact_transactions));
SELECT dq_record('Accuracy','Snapshot reconciliation: SUM(txn_count) vs fact rows',
       (SELECT COUNT(*) FROM fact_transactions), (SELECT SUM(txn_count) FROM fact_daily_fraud_snapshot));
SELECT dq_record('Accuracy','Snapshot reconciliation: SUM(fraud_txn_count) vs SUM(is_fraud)',
       (SELECT SUM(is_fraud) FROM fact_transactions), (SELECT SUM(fraud_txn_count) FROM fact_daily_fraud_snapshot));
SELECT dq_record('Accuracy','Snapshot reconciliation: SUM(total_amount) vs SUM(amount)',
       (SELECT SUM(amount) FROM fact_transactions), (SELECT SUM(total_amount) FROM fact_daily_fraud_snapshot));
SELECT dq_record('Accuracy','Snapshot reconciliation: SUM(fraud_amount) vs fact',
       (SELECT SUM(fraud_amount) FROM fact_transactions), (SELECT SUM(fraud_amount) FROM fact_daily_fraud_snapshot));
SELECT dq_record('Accuracy','Rows where fraud_amount <> amount x is_fraud',
       0, (SELECT COUNT(*) FROM fact_transactions WHERE fraud_amount <> amount * is_fraud));
SELECT dq_record('Accuracy','Rows with amount <= 0', 0, (SELECT COUNT(*) FROM fact_transactions WHERE amount <= 0));
SELECT dq_record('Accuracy','Rows with risk_score outside 0-100', 0, (SELECT COUNT(*) FROM fact_transactions WHERE risk_score < 0 OR risk_score > 100));
SELECT dq_record('Accuracy','Rows with is_fraud not 0 or 1', 0, (SELECT COUNT(*) FROM fact_transactions WHERE is_fraud NOT IN (0,1)));
SELECT dq_record('Accuracy','Rows with a date outside 2022', 0, (SELECT COUNT(*) FROM fact_transactions WHERE date_key NOT BETWEEN 20220101 AND 20221231));
SELECT dq_record('Accuracy','Rows where date_key does not match txn_timestamp',
       0, (SELECT COUNT(*) FROM fact_transactions WHERE date_key <> TO_CHAR(txn_timestamp,'YYYYMMDD')::INT));
SELECT dq_record('Accuracy','Rows where time_key does not match the hour of txn_timestamp',
       0, (SELECT COUNT(*) FROM fact_transactions WHERE time_key <> EXTRACT(HOUR FROM txn_timestamp)::INT));
SELECT dq_record('Accuracy','Rows where anomaly level contradicts risk score (Low <60, Moderate 60-89, High >=90)',
       0, (SELECT COUNT(*) FROM fact_transactions f JOIN dim_behaviorrisk b ON b.behavior_key = f.behavior_key
           WHERE (b.anomaly_level = 'Low Risk' AND f.risk_score >= 60) OR (b.anomaly_level = 'Moderate Risk' AND (f.risk_score < 60 OR f.risk_score >= 90))
              OR (b.anomaly_level = 'High Risk' AND f.risk_score < 90)));
SELECT dq_record('Accuracy','Snapshot rows where fraud_rate differs from fraud_txn_count / txn_count',
       0, (SELECT COUNT(*) FROM fact_daily_fraud_snapshot WHERE ABS(fraud_rate - fraud_txn_count::NUMERIC / txn_count) > 0.0001));
SELECT dq_record('Accuracy','Fact rows whose behaviour band does not match the stored login_frequency / session_duration',
       0, (SELECT COUNT(*) FROM fact_transactions f JOIN dim_behaviorrisk b ON b.behavior_key = f.behavior_key
           WHERE b.login_frequency_band <> CASE WHEN f.login_frequency <= 3 THEN 'Low' WHEN f.login_frequency <= 6 THEN 'Medium' ELSE 'High' END
              OR b.session_duration_band <> CASE WHEN f.session_duration < 35 THEN 'Short' WHEN f.session_duration < 100 THEN 'Medium' ELSE 'Long' END));

-- =============================== INTEGRITY ===============================
SELECT dq_record('Integrity','Fact rows without matching dim_date', 0,
       (SELECT COUNT(*) FROM fact_transactions f LEFT JOIN dim_date d ON d.date_key = f.date_key WHERE d.date_key IS NULL));
SELECT dq_record('Integrity','Fact rows without matching dim_time', 0,
       (SELECT COUNT(*) FROM fact_transactions f LEFT JOIN dim_time d ON d.time_key = f.time_key WHERE d.time_key IS NULL));
SELECT dq_record('Integrity','Fact rows without matching dim_customer', 0,
       (SELECT COUNT(*) FROM fact_transactions f LEFT JOIN dim_customer d ON d.customer_key = f.customer_key WHERE d.customer_key IS NULL));
SELECT dq_record('Integrity','Fact rows without matching dim_merchant', 0,
       (SELECT COUNT(*) FROM fact_transactions f LEFT JOIN dim_merchant d ON d.merchant_key = f.merchant_key WHERE d.merchant_key IS NULL));
SELECT dq_record('Integrity','Fact rows without matching dim_transactiontype', 0,
       (SELECT COUNT(*) FROM fact_transactions f LEFT JOIN dim_transactiontype d ON d.type_key = f.type_key WHERE d.type_key IS NULL));
SELECT dq_record('Integrity','Fact rows without matching dim_behaviorrisk', 0,
       (SELECT COUNT(*) FROM fact_transactions f LEFT JOIN dim_behaviorrisk d ON d.behavior_key = f.behavior_key WHERE d.behavior_key IS NULL));
SELECT dq_record('Integrity','Snapshot rows without matching dim_date or dim_transactiontype', 0,
       (SELECT COUNT(*) FROM fact_daily_fraud_snapshot s LEFT JOIN dim_date d ON d.date_key = s.date_key LEFT JOIN dim_transactiontype t ON t.type_key = s.type_key
        WHERE d.date_key IS NULL OR t.type_key IS NULL));
SELECT dq_record('Integrity','Customer-merchant rows without matching dim_customer or dim_merchant', 0,
       (SELECT COUNT(*) FROM fact_customer_merchant x LEFT JOIN dim_customer c ON c.customer_key = x.customer_key LEFT JOIN dim_merchant m ON m.merchant_key = x.merchant_key
        WHERE c.customer_key IS NULL OR m.merchant_key IS NULL));
SELECT dq_record('Integrity','Fact rows without matching dimension (all six dimensions together)', 0,
       (SELECT COUNT(*) FROM fact_transactions f
        LEFT JOIN dim_date d1 ON d1.date_key = f.date_key LEFT JOIN dim_time d2 ON d2.time_key = f.time_key
        LEFT JOIN dim_customer d3 ON d3.customer_key = f.customer_key LEFT JOIN dim_merchant d4 ON d4.merchant_key = f.merchant_key
        LEFT JOIN dim_transactiontype d5 ON d5.type_key = f.type_key LEFT JOIN dim_behaviorrisk d6 ON d6.behavior_key = f.behavior_key
        WHERE d1.date_key IS NULL OR d2.time_key IS NULL OR d3.customer_key IS NULL OR d4.merchant_key IS NULL OR d5.type_key IS NULL OR d6.behavior_key IS NULL));
SELECT dq_record('Integrity','Duplicate transaction_key in fact_transactions', 0,
       (SELECT COUNT(*) FROM (SELECT transaction_key FROM fact_transactions GROUP BY 1 HAVING COUNT(*) > 1) x));
SELECT dq_record('Integrity','Duplicate (date_key, type_key) in the snapshot', 0,
       (SELECT COUNT(*) FROM (SELECT 1 FROM fact_daily_fraud_snapshot GROUP BY date_key, type_key HAVING COUNT(*) > 1) x));
SELECT dq_record('Integrity','Duplicate business keys in dim_customer', 0,
       (SELECT COUNT(*) FROM (SELECT 1 FROM dim_customer GROUP BY customer_email HAVING COUNT(*) > 1) x));
SELECT dq_record('Integrity','Duplicate business keys in dim_merchant', 0,
       (SELECT COUNT(*) FROM (SELECT 1 FROM dim_merchant GROUP BY merchant_email HAVING COUNT(*) > 1) x));
SELECT dq_record('Integrity','Duplicate business keys in dim_transactiontype', 0,
       (SELECT COUNT(*) FROM (SELECT 1 FROM dim_transactiontype GROUP BY type_name, location_region, ip_prefix HAVING COUNT(*) > 1) x));
SELECT dq_record('Integrity','Duplicate business keys in dim_behaviorrisk', 0,
       (SELECT COUNT(*) FROM (SELECT 1 FROM dim_behaviorrisk GROUP BY purchase_pattern, anomaly_level, login_frequency_band, session_duration_band HAVING COUNT(*) > 1) x));
SELECT dq_record('Integrity','Surrogate key: every staged user record maps to exactly one customer_key', 0,
       (SELECT COUNT(*) FROM stg_user u LEFT JOIN dim_customer c ON c.customer_email = u.customer_email WHERE c.customer_key IS NULL));
SELECT dq_record('Integrity','Surrogate key: every staged user record maps to exactly one merchant_key', 0,
       (SELECT COUNT(*) FROM stg_user u LEFT JOIN dim_merchant m ON m.merchant_email = u.merchant_email WHERE m.merchant_key IS NULL));
SELECT dq_record('Integrity','Surrogate keys are unique (distinct customer_key = rows)',
       (SELECT COUNT(*) FROM dim_customer), (SELECT COUNT(DISTINCT customer_key) FROM dim_customer));
SELECT dq_record('Integrity','Surrogate key numbering starts at 1001 for dim_customer', 1001, (SELECT MIN(customer_key) FROM dim_customer));
SELECT dq_record('Integrity','Customers never used by any transaction (orphan dimension members)', 0,
       (SELECT COUNT(*) FROM dim_customer c WHERE NOT EXISTS (SELECT 1 FROM fact_transactions f WHERE f.customer_key = c.customer_key)),
       '=', 'Informational: dimension members without facts');
SELECT dq_record('Integrity','Merchants never used by any transaction (orphan dimension members)', 0,
       (SELECT COUNT(*) FROM dim_merchant m WHERE NOT EXISTS (SELECT 1 FROM fact_transactions f WHERE f.merchant_key = m.merchant_key)),
       '=', 'Informational: dimension members without facts');
