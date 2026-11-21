# Real-time Data Warehouse for Fraud Detection & Anomaly Analysis - Phase 2

Data Warehousing & Business Intelligence - Final Project, Phase 2 (Physical Data Warehouse Implementation & ETL Pipeline)

Team: Chaudary Moaz Kashif (23L-2626), Umar Khalid (23L-2599)

## Architecture

```
Source CSV files  ->  project_staging  ->  project_dw  ->  project_reporting
 (data/*.csv)         raw_* , stg_*        dim_* , fact_*      vw_* views for Power BI / Tableau
```

| Schema | Content |
|---|---|
| `project_staging` | `raw_*` landing tables (all text), `stg_*` cleaned and typed tables, `rejected_rows`, `cleaning_log` |
| `project_dw` | 6 dimensions, 3 fact tables (transaction, daily snapshot, factless), `etl_audit_log`, `dq_results` |
| `project_reporting` | 15 views answering the 13 business questions of Phase 1 |

The dimensional model is the Phase 1 design (see `docs/`).

## Repository layout

| Path | Purpose (Phase 2 deliverable) |
|---|---|
| `sql/00_create_database.sql` | PostgreSQL database script |
| `sql/01_create_schemas.sql` | Creates `project_staging`, `project_dw`, `project_reporting` |
| `sql/02_staging_ddl.sql` | Staging Schema SQL |
| `sql/03_staging_clean.sql` | Staging transformations: remove duplicates, handle NULLs, standardise text, convert types |
| `sql/04_dw_ddl.sql` | DW Schema SQL (surrogate keys, foreign keys, constraints) |
| `sql/05_load_dimensions.sql` | Dimension Load Scripts |
| `sql/06_load_facts.sql` | Fact Load Scripts (business key -> surrogate key mapping) |
| `sql/07_reporting_views.sql` | Reporting schema views |
| `sql/08_data_quality.sql` | Data quality validation (completeness, accuracy, integrity) |
| `sql/run_all_psql.sql` | Runs everything with `psql` only |
| `etl/etl_pipeline.py` | ETL script (Python orchestration: COPY extract, SQL transform and load, audit log) |
| `etl/generate_reports.py` | Builds the two PDF reports from the live database |
| `reports/Data_Cleaning_Report.pdf` | Data Cleaning Report |
| `reports/Data_Quality_Report.pdf` | Data Quality Report |
| `docs/` | Phase 1 design: schema diagram, data dictionary |
| `data/` | Put the four source CSV files here (they are not committed) |

## How to run

Requirements: PostgreSQL 13+ and Python 3.9+.

```bash
pip install -r requirements.txt
# copy accounts.csv, transaction_type.csv, behavior_risk.csv, user.csv into data/

# Option A - Python pipeline (creates the database if it does not exist)
python etl/etl_pipeline.py --data-dir data --host localhost --user postgres --password <password>
python etl/generate_reports.py --host localhost --user postgres --password <password>

# Option B - psql only
psql -U postgres -f sql/00_create_database.sql
psql -U postgres -d fraud_dw -f sql/run_all_psql.sql
```

The pipeline stops on the first error and exits with code 1 if any data quality check fails.

## Surrogate keys

* `dim_customer.customer_key` starts at 1001, `dim_merchant.merchant_key` at 5001, other dimensions use generated integers;
  `dim_date.date_key` is `yyyymmdd`, `dim_time.time_key` is the hour.
* The business key stays in the dimension as a unique column (for example `customer_email`).
* `06_load_facts.sql` replaces every business key with the surrogate key by joining to the dimensions. A missing match leaves a NULL, and the NOT NULL
  constraint stops the load, so no fact row is dropped silently.

## Linking the four source files (assumption A1)

The source files share no key. The fact load links them with a fixed positional rule (accounts row n -> transaction context
row ((n-1) mod 37,417)+1 and user row ((n-1) mod 2,000)+1). There is no `RANDOM()`, so every run gives the same result.
Results that combine information from different files are therefore simulated associations.

## Results of the last run (full source files)

* 1,048,575 transactions loaded; 4,498 dimension rows; 23,370 snapshot rows; 2,000 customer-merchant links
* 55 data quality checks: 55 passed, 0 failed
* Full run takes about one minute on a laptop-class machine
