-- 03_staging_clean.sql  -  STAGING TRANSFORMATIONS (raw_* -> stg_*)
-- Applies: remove duplicates, handle NULLs, standardise text, convert data types.
-- Every rule writes a line to project_staging.cleaning_log (used by the Data Cleaning Report).
SET search_path TO project_staging;

TRUNCATE stg_accounts, stg_transaction_type, stg_behavior_risk, stg_user, stg_customer, stg_merchant, rejected_rows, cleaning_log RESTART IDENTITY;

-- =====================================================================
-- 1. accounts.csv  ->  stg_accounts
-- =====================================================================
-- 1a. Handle NULLs / invalid values: reject rows with missing accounts, non-numeric amount or unknown fraud flag
INSERT INTO rejected_rows (source_table, row_id, reason, raw_data)
SELECT 'raw_accounts', row_id,
       CASE WHEN NULLIF(TRIM(sender_account),'') IS NULL OR NULLIF(TRIM(receiver_account),'') IS NULL THEN 'Missing account'
            WHEN TRIM(amount) !~ '^[0-9]+(\.[0-9]+)?$' OR amount IS NULL THEN 'Amount missing or not numeric'
            ELSE 'is_fraud not TRUE/FALSE' END,
       concat_ws(',', sender_account, receiver_account, amount, is_fraud)
FROM raw_accounts
WHERE NULLIF(TRIM(sender_account),'') IS NULL OR NULLIF(TRIM(receiver_account),'') IS NULL
   OR amount IS NULL OR TRIM(amount) !~ '^[0-9]+(\.[0-9]+)?$'
   OR UPPER(TRIM(is_fraud)) NOT IN ('TRUE','FALSE') OR is_fraud IS NULL;

-- 1b. Standardise text (upper case, trimmed), convert types, remove exact duplicates, number the rows in file order
INSERT INTO stg_accounts (txn_seq, sender_account, receiver_account, amount, is_fraud)
SELECT ROW_NUMBER() OVER (ORDER BY first_row), sender_account, receiver_account, amount, is_fraud
FROM (
    SELECT MIN(row_id) AS first_row,
           UPPER(TRIM(sender_account))   AS sender_account,
           UPPER(TRIM(receiver_account)) AS receiver_account,
           TRIM(amount)::NUMERIC(12,2)   AS amount,
           CASE UPPER(TRIM(is_fraud)) WHEN 'TRUE' THEN 1 ELSE 0 END::SMALLINT AS is_fraud
    FROM raw_accounts r
    WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table = 'raw_accounts' AND x.row_id = r.row_id)
    GROUP BY 2, 3, 4, 5           -- identical rows collapse into one (duplicate removal)
) d;

INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'accounts.csv', 'Reject rows with missing / invalid values', 'NULL handling',
       (SELECT COUNT(*) FROM raw_accounts), (SELECT COUNT(*) FROM raw_accounts) - (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_accounts'),
       (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_accounts'), 'Missing account, non-numeric amount or unknown is_fraud';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'accounts.csv', 'Remove exact duplicate rows', 'Duplicates',
       (SELECT COUNT(*) FROM raw_accounts) - (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_accounts'),
       (SELECT COUNT(*) FROM stg_accounts),
       (SELECT COUNT(*) FROM raw_accounts) - (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_accounts') - (SELECT COUNT(*) FROM stg_accounts),
       'Rows identical in all four columns';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'accounts.csv', 'Convert amount TEXT -> NUMERIC(12,2) and is_fraud TRUE/FALSE -> 1/0', 'Data type conversion',
       (SELECT COUNT(*) FROM stg_accounts), (SELECT COUNT(*) FROM stg_accounts), (SELECT COUNT(*) FROM stg_accounts), 'All rows converted';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'accounts.csv', 'Upper-case and trim account IDs', 'Standardise text',
       (SELECT COUNT(*) FROM stg_accounts), (SELECT COUNT(*) FROM stg_accounts),
       (SELECT COUNT(*) FROM raw_accounts WHERE sender_account <> UPPER(TRIM(sender_account)) OR receiver_account <> UPPER(TRIM(receiver_account))),
       'Rows whose account text actually changed';

-- =====================================================================
-- 2. transaction_type.csv  ->  stg_transaction_type
-- =====================================================================
-- 2a. Blank rows (all columns empty) and incomplete rows are rejected
INSERT INTO rejected_rows (source_table, row_id, reason, raw_data)
SELECT 'raw_transaction_type', row_id,
       CASE WHEN COALESCE(NULLIF(TRIM(transaction_id),''), NULLIF(TRIM(transaction_type),''), NULLIF(TRIM(location_region),''),
                          NULLIF(TRIM(ip_prefix),''), NULLIF(TRIM(txn_timestamp),'')) IS NULL
            THEN 'Completely blank row' ELSE 'Incomplete or invalid row' END,
       concat_ws(',', transaction_id, transaction_type, location_region, ip_prefix, txn_timestamp)
FROM raw_transaction_type
WHERE NOT (TRIM(COALESCE(transaction_id,'')) ~ '^[0-9]+$'
           AND NULLIF(TRIM(transaction_type),'') IS NOT NULL AND NULLIF(TRIM(location_region),'') IS NOT NULL
           AND NULLIF(TRIM(ip_prefix),'') IS NOT NULL
           AND TRIM(COALESCE(txn_timestamp,'')) ~ '^[0-3][0-9]/[0-1][0-9]/[0-9]{4} [0-2][0-9]:[0-5][0-9]$');

-- 2b. Standardise text (INITCAP), convert timestamp text DD/MM/YYYY HH24:MI -> TIMESTAMP, remove duplicate transaction_id
INSERT INTO stg_transaction_type (transaction_id, type_name, location_region, ip_prefix, txn_timestamp)
SELECT DISTINCT ON (TRIM(transaction_id)::INTEGER)
       TRIM(transaction_id)::INTEGER,
       INITCAP(LOWER(TRIM(transaction_type))),
       INITCAP(LOWER(TRIM(location_region))),
       TRIM(ip_prefix),
       TO_TIMESTAMP(TRIM(txn_timestamp), 'DD/MM/YYYY HH24:MI')::TIMESTAMP
FROM raw_transaction_type r
WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table='raw_transaction_type' AND x.row_id = r.row_id)
ORDER BY TRIM(transaction_id)::INTEGER, row_id;

INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'transaction_type.csv', 'Remove completely blank rows', 'NULL handling',
       (SELECT COUNT(*) FROM raw_transaction_type),
       (SELECT COUNT(*) FROM raw_transaction_type) - (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_transaction_type' AND reason='Completely blank row'),
       (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_transaction_type' AND reason='Completely blank row'),
       'Rows where every column is empty';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'transaction_type.csv', 'Reject incomplete / invalid rows', 'NULL handling',
       (SELECT COUNT(*) FROM raw_transaction_type) - (SELECT COUNT(*) FROM rejected_rows WHERE reason='Completely blank row'),
       (SELECT COUNT(*) FROM stg_transaction_type),
       (SELECT COUNT(*) FROM rejected_rows WHERE reason='Incomplete or invalid row'),
       'Missing field or unreadable timestamp';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'transaction_type.csv', 'Remove duplicate transaction_id', 'Duplicates',
       (SELECT COUNT(*) FROM raw_transaction_type) - (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_transaction_type'),
       (SELECT COUNT(*) FROM stg_transaction_type),
       (SELECT COUNT(*) FROM raw_transaction_type) - (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_transaction_type') - (SELECT COUNT(*) FROM stg_transaction_type),
       'Keeps the first occurrence';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'transaction_type.csv', 'INITCAP type and region (transfer -> Transfer)', 'Standardise text',
       (SELECT COUNT(*) FROM stg_transaction_type), (SELECT COUNT(*) FROM stg_transaction_type),
       (SELECT COUNT(*) FROM raw_transaction_type WHERE transaction_type IS NOT NULL AND transaction_type <> INITCAP(LOWER(TRIM(transaction_type)))),
       'Rows whose type text actually changed';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'transaction_type.csv', 'Convert timestamp text DD/MM/YYYY HH:MI -> TIMESTAMP', 'Data type conversion',
       (SELECT COUNT(*) FROM stg_transaction_type), (SELECT COUNT(*) FROM stg_transaction_type), (SELECT COUNT(*) FROM stg_transaction_type), 'All valid rows converted';

-- =====================================================================
-- 3. behavior_risk.csv  ->  stg_behavior_risk
-- =====================================================================
INSERT INTO rejected_rows (source_table, row_id, reason, raw_data)
SELECT 'raw_behavior_risk', row_id, 'Missing or non-numeric login_frequency / session_duration / risk_score',
       concat_ws(',', login_frequency, session_duration, purchase_pattern, risk_score, anomaly)
FROM raw_behavior_risk
WHERE TRIM(COALESCE(login_frequency,'')) !~ '^[0-9]+$'
   OR TRIM(COALESCE(session_duration,'')) !~ '^[0-9]+(\.[0-9]+)?$'
   OR TRIM(COALESCE(risk_score,'')) !~ '^[0-9]+(\.[0-9]+)?$';

INSERT INTO stg_behavior_risk (row_id, login_frequency, session_duration, purchase_pattern, risk_score, anomaly_level,
                               login_frequency_band, session_duration_band)
SELECT row_id,
       TRIM(login_frequency)::SMALLINT,
       TRIM(session_duration)::NUMERIC(10,2),
       COALESCE(NULLIF(INITCAP(REPLACE(LOWER(TRIM(purchase_pattern)),'_',' ')),''), 'Unknown'),
       TRIM(risk_score)::NUMERIC(5,2),
       COALESCE(NULLIF(INITCAP(REPLACE(LOWER(TRIM(anomaly)),'_',' ')),''), 'Unknown'),
       CASE WHEN TRIM(login_frequency)::INT <= 3 THEN 'Low' WHEN TRIM(login_frequency)::INT <= 6 THEN 'Medium' ELSE 'High' END,
       CASE WHEN TRIM(session_duration)::NUMERIC < 35 THEN 'Short' WHEN TRIM(session_duration)::NUMERIC < 100 THEN 'Medium' ELSE 'Long' END
FROM raw_behavior_risk r
WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table='raw_behavior_risk' AND x.row_id = r.row_id);

INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'behavior_risk.csv', 'Reject rows with missing / non-numeric measures', 'NULL handling',
       (SELECT COUNT(*) FROM raw_behavior_risk), (SELECT COUNT(*) FROM stg_behavior_risk),
       (SELECT COUNT(*) FROM rejected_rows WHERE source_table='raw_behavior_risk'), 'login_frequency, session_duration, risk_score';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'behavior_risk.csv', 'Missing purchase_pattern / anomaly -> ''Unknown''', 'NULL handling',
       (SELECT COUNT(*) FROM stg_behavior_risk), (SELECT COUNT(*) FROM stg_behavior_risk),
       (SELECT COUNT(*) FROM stg_behavior_risk WHERE purchase_pattern='Unknown' OR anomaly_level='Unknown'), 'Default value for text columns';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'behavior_risk.csv', 'Readable labels (high_value -> High Value, low_risk -> Low Risk)', 'Standardise text',
       (SELECT COUNT(*) FROM stg_behavior_risk), (SELECT COUNT(*) FROM stg_behavior_risk),
       (SELECT COUNT(*) FROM raw_behavior_risk WHERE purchase_pattern <> INITCAP(REPLACE(LOWER(TRIM(purchase_pattern)),'_',' ')) OR anomaly <> INITCAP(REPLACE(LOWER(TRIM(anomaly)),'_',' '))),
       'Rows whose label text actually changed';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'behavior_risk.csv', 'Convert text -> SMALLINT / NUMERIC and derive login and session bands', 'Data type conversion',
       (SELECT COUNT(*) FROM stg_behavior_risk), (SELECT COUNT(*) FROM stg_behavior_risk), (SELECT COUNT(*) FROM stg_behavior_risk), 'All rows converted';

-- =====================================================================
-- 4. user.csv  ->  stg_user, stg_customer, stg_merchant
-- =====================================================================
INSERT INTO rejected_rows (source_table, row_id, reason, raw_data)
SELECT 'raw_user', row_id, 'Missing customer or merchant email',
       concat_ws(',', customer_name, customer_email, merchant_name, merchant_email)
FROM raw_user
WHERE NULLIF(TRIM(customer_email),'') IS NULL OR NULLIF(TRIM(merchant_email),'') IS NULL;

INSERT INTO stg_user (row_id, customer_email, merchant_email)
SELECT row_id, LOWER(TRIM(customer_email)), LOWER(TRIM(merchant_email))
FROM raw_user r
WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table='raw_user' AND x.row_id = r.row_id);

-- customers: standardise text, parse card expiry (Mon-YY), default device, REMOVE DUPLICATE EMAILS (keep first row)
INSERT INTO stg_customer (customer_email, customer_name, device_type, card_expiry_month, card_expiry_year)
SELECT DISTINCT ON (LOWER(TRIM(customer_email)))
       LOWER(TRIM(customer_email)),
       COALESCE(NULLIF(INITCAP(TRIM(customer_name)),''), 'Unknown'),
       COALESCE(NULLIF(INITCAP(LOWER(TRIM(device_type))),''), 'Unknown'),
       CASE WHEN TRIM(card_expiry) ~ '^[A-Za-z]{3}-[0-9]{2}$' THEN EXTRACT(MONTH FROM TO_DATE(SPLIT_PART(TRIM(card_expiry),'-',1),'Mon'))::SMALLINT END,
       CASE WHEN TRIM(card_expiry) ~ '^[A-Za-z]{3}-[0-9]{2}$' THEN (2000 + SPLIT_PART(TRIM(card_expiry),'-',2)::INT)::SMALLINT END
FROM raw_user r
WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table='raw_user' AND x.row_id = r.row_id)
ORDER BY LOWER(TRIM(customer_email)), row_id;

INSERT INTO stg_merchant (merchant_email, merchant_name)
SELECT DISTINCT ON (LOWER(TRIM(merchant_email)))
       LOWER(TRIM(merchant_email)), COALESCE(NULLIF(INITCAP(TRIM(merchant_name)),''), 'Unknown')
FROM raw_user r
WHERE NOT EXISTS (SELECT 1 FROM rejected_rows x WHERE x.source_table='raw_user' AND x.row_id = r.row_id)
ORDER BY LOWER(TRIM(merchant_email)), row_id;

INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'user.csv', 'Remove duplicate customer emails', 'Duplicates',
       (SELECT COUNT(*) FROM stg_user), (SELECT COUNT(*) FROM stg_customer),
       (SELECT COUNT(*) FROM stg_user) - (SELECT COUNT(*) FROM stg_customer), 'First record per email is kept';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'user.csv', 'Remove duplicate merchant emails', 'Duplicates',
       (SELECT COUNT(*) FROM stg_user), (SELECT COUNT(*) FROM stg_merchant),
       (SELECT COUNT(*) FROM stg_user) - (SELECT COUNT(*) FROM stg_merchant), 'First record per email is kept';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'user.csv', 'Default missing names and device to ''Unknown''', 'NULL handling',
       (SELECT COUNT(*) FROM stg_customer), (SELECT COUNT(*) FROM stg_customer),
       (SELECT COUNT(*) FROM stg_customer WHERE customer_name='Unknown' OR device_type='Unknown')
     + (SELECT COUNT(*) FROM stg_merchant WHERE merchant_name='Unknown'), 'Default value for text columns';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'user.csv', 'INITCAP names and device, LOWER emails, trim spaces', 'Standardise text',
       (SELECT COUNT(*) FROM stg_user), (SELECT COUNT(*) FROM stg_user),
       (SELECT COUNT(*) FROM raw_user WHERE customer_name <> INITCAP(TRIM(customer_name)) OR device_type <> INITCAP(LOWER(TRIM(device_type)))
            OR customer_email <> LOWER(TRIM(customer_email)) OR merchant_email <> LOWER(TRIM(merchant_email))),
       'Rows whose text actually changed';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'user.csv', 'Parse Card_Expiry Mon-YY -> month and year numbers', 'Data type conversion',
       (SELECT COUNT(*) FROM stg_customer), (SELECT COUNT(*) FROM stg_customer),
       (SELECT COUNT(*) FROM stg_customer WHERE card_expiry_month IS NOT NULL), 'Customers with a valid expiry';
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'user.csv', 'Card_Number NOT loaded (scientific notation, sensitive)', 'Data privacy / quality',
       (SELECT COUNT(*) FROM raw_user), (SELECT COUNT(*) FROM raw_user),
       (SELECT COUNT(*) FROM raw_user WHERE card_number ~* '^[0-9.]+E\+[0-9]+$'), 'Rows where the card number is in scientific notation, e.g. 4.17562E+18';

-- Rejected-row summary entry
INSERT INTO cleaning_log (source_table, rule_name, rule_type, rows_before, rows_after, rows_affected, note)
SELECT 'ALL', 'Total rows written to rejected_rows', 'Summary', NULL, NULL, COUNT(*), 'See project_staging.rejected_rows' FROM rejected_rows;

ANALYZE stg_accounts; ANALYZE stg_transaction_type; ANALYZE stg_behavior_risk; ANALYZE stg_user;
