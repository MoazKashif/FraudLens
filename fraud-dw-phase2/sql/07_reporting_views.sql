-- 07_reporting_views.sql  -  REPORTING SCHEMA (views for Power BI / Tableau)
-- One view per dashboard block from the Phase 1 business questions (Q1-Q13).
SET search_path TO project_reporting, project_dw;

-- Q1, Q2  Overview Dashboard / KPI Cards
CREATE OR REPLACE VIEW project_reporting.vw_kpi_overview AS
SELECT COUNT(*)                                             AS total_transactions,
       SUM(amount)                                          AS total_amount,
       SUM(is_fraud)                                        AS fraud_transactions,
       ROUND(100.0 * SUM(is_fraud) / COUNT(*), 2)           AS fraud_pct,
       SUM(fraud_amount)                                    AS total_fraud_loss,
       ROUND(AVG(amount), 2)                                AS avg_transaction_value,
       ROUND(AVG(amount) FILTER (WHERE is_fraud = 1), 2)    AS avg_fraud_amount,
       ROUND(AVG(amount) FILTER (WHERE is_fraud = 0), 2)    AS avg_normal_amount,
       ROUND(AVG(risk_score), 2)                            AS avg_risk_score
FROM project_dw.fact_transactions;

-- Q3  Monthly fraud trend (from the snapshot)
CREATE OR REPLACE VIEW project_reporting.vw_fraud_trend_monthly AS
SELECT d.year, d.month_number, d.month_name,
       SUM(s.txn_count) AS transactions, SUM(s.fraud_txn_count) AS fraud_transactions,
       ROUND(100.0 * SUM(s.fraud_txn_count) / SUM(s.txn_count), 2) AS fraud_pct,
       SUM(s.fraud_amount) AS fraud_amount
FROM project_dw.fact_daily_fraud_snapshot s
JOIN project_dw.dim_date d ON d.date_key = s.date_key
GROUP BY d.year, d.month_number, d.month_name;

-- Q3  Daily fraud trend (from the snapshot)
CREATE OR REPLACE VIEW project_reporting.vw_fraud_trend_daily AS
SELECT d.full_date, d.day_name, d.is_weekend,
       SUM(s.txn_count) AS transactions, SUM(s.fraud_txn_count) AS fraud_transactions,
       ROUND(100.0 * SUM(s.fraud_txn_count) / SUM(s.txn_count), 2) AS fraud_pct, SUM(s.fraud_amount) AS fraud_amount
FROM project_dw.fact_daily_fraud_snapshot s
JOIN project_dw.dim_date d ON d.date_key = s.date_key
GROUP BY d.full_date, d.day_name, d.is_weekend;

-- Q4  Fraud by hour and day part
CREATE OR REPLACE VIEW project_reporting.vw_fraud_by_hour AS
SELECT t.day_part, t.hour_of_day, t.hour_label, COUNT(*) AS transactions, SUM(f.is_fraud) AS fraud_transactions,
       ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 3) AS fraud_pct
FROM project_dw.fact_transactions f JOIN project_dw.dim_time t ON t.time_key = f.time_key
GROUP BY t.day_part, t.hour_of_day, t.hour_label;

-- Q5, Q6  Transaction type, region and IP prefix
CREATE OR REPLACE VIEW project_reporting.vw_fraud_by_type AS
SELECT ty.type_name, ty.money_direction, COUNT(*) AS transactions, SUM(f.amount) AS total_amount,
       SUM(f.is_fraud) AS fraud_transactions, ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 3) AS fraud_pct
FROM project_dw.fact_transactions f JOIN project_dw.dim_transactiontype ty ON ty.type_key = f.type_key
GROUP BY ty.type_name, ty.money_direction;

CREATE OR REPLACE VIEW project_reporting.vw_fraud_by_region_ip AS
SELECT ty.location_region, ty.ip_prefix, COUNT(*) AS transactions, SUM(f.is_fraud) AS fraud_transactions,
       ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 3) AS fraud_pct
FROM project_dw.fact_transactions f JOIN project_dw.dim_transactiontype ty ON ty.type_key = f.type_key
GROUP BY ty.location_region, ty.ip_prefix;

-- Q7, Q8  Behaviour and risk
CREATE OR REPLACE VIEW project_reporting.vw_fraud_by_behavior AS
SELECT b.anomaly_level, b.purchase_pattern, COUNT(*) AS transactions, SUM(f.is_fraud) AS fraud_transactions,
       ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 3) AS fraud_pct, ROUND(AVG(f.risk_score), 2) AS avg_risk_score,
       ROUND(AVG(f.login_frequency), 2) AS avg_logins, ROUND(AVG(f.session_duration), 2) AS avg_session
FROM project_dw.fact_transactions f JOIN project_dw.dim_behaviorrisk b ON b.behavior_key = f.behavior_key
GROUP BY b.anomaly_level, b.purchase_pattern;

CREATE OR REPLACE VIEW project_reporting.vw_behavior_by_fraud_flag AS
SELECT CASE f.is_fraud WHEN 1 THEN 'Fraud' ELSE 'Normal' END AS fraud_status, COUNT(*) AS transactions,
       ROUND(AVG(f.risk_score), 2) AS avg_risk_score, ROUND(AVG(f.login_frequency), 2) AS avg_logins,
       ROUND(AVG(f.session_duration), 2) AS avg_session
FROM project_dw.fact_transactions f GROUP BY f.is_fraud;

-- Q9  Top risky customers (customer email is masked for reports)
CREATE OR REPLACE VIEW project_reporting.vw_top_risky_customers AS
SELECT c.customer_key, c.customer_name,
       LEFT(c.customer_email, 2) || '***@' || SPLIT_PART(c.customer_email, '@', 2) AS customer_email_masked,
       COUNT(*) AS transactions, SUM(f.is_fraud) AS fraud_transactions,
       ROUND(1.0 * SUM(f.is_fraud) / COUNT(*), 4) AS fraud_ratio, SUM(f.fraud_amount) AS fraud_amount
FROM project_dw.fact_transactions f JOIN project_dw.dim_customer c ON c.customer_key = f.customer_key
GROUP BY c.customer_key, c.customer_name, c.customer_email;

-- Q10  Merchants linked to fraud
CREATE OR REPLACE VIEW project_reporting.vw_top_merchants_fraud AS
SELECT m.merchant_key, m.merchant_name, COUNT(*) AS transactions, SUM(f.is_fraud) AS fraud_transactions,
       SUM(f.fraud_amount) AS fraud_value, ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 3) AS fraud_pct
FROM project_dw.fact_transactions f JOIN project_dw.dim_merchant m ON m.merchant_key = f.merchant_key
GROUP BY m.merchant_key, m.merchant_name;

-- Q11  Repeat-fraud sender accounts
CREATE OR REPLACE VIEW project_reporting.vw_repeat_fraud_accounts AS
SELECT sender_account, COUNT(*) AS transactions, SUM(is_fraud) AS fraud_transactions,
       SUM(amount) AS amount_sent, SUM(fraud_amount) AS fraud_amount
FROM project_dw.fact_transactions
GROUP BY sender_account HAVING SUM(is_fraud) >= 2;

-- Q11  Largest receivers
CREATE OR REPLACE VIEW project_reporting.vw_top_receivers AS
SELECT receiver_account, COUNT(*) AS transactions_received, SUM(amount) AS amount_received, SUM(fraud_amount) AS fraud_received
FROM project_dw.fact_transactions GROUP BY receiver_account;

-- Q12  Fraud by device type
CREATE OR REPLACE VIEW project_reporting.vw_fraud_by_device AS
SELECT c.device_type, COUNT(*) AS transactions, SUM(f.is_fraud) AS fraud_transactions,
       ROUND(100.0 * SUM(f.is_fraud) / COUNT(*), 3) AS fraud_pct
FROM project_dw.fact_transactions f JOIN project_dw.dim_customer c ON c.customer_key = f.customer_key
GROUP BY c.device_type;

-- Q13  Customer-merchant network (factless fact)
CREATE OR REPLACE VIEW project_reporting.vw_merchant_customer_links AS
SELECT m.merchant_key, m.merchant_name, COUNT(DISTINCT fcm.customer_key) AS linked_customers
FROM project_dw.fact_customer_merchant fcm JOIN project_dw.dim_merchant m ON m.merchant_key = fcm.merchant_key
GROUP BY m.merchant_key, m.merchant_name;

CREATE OR REPLACE VIEW project_reporting.vw_customers_without_merchant AS
SELECT c.customer_key, c.customer_name
FROM project_dw.dim_customer c
LEFT JOIN project_dw.fact_customer_merchant fcm ON fcm.customer_key = c.customer_key
WHERE fcm.customer_key IS NULL;
