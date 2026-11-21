-- 01_create_schemas.sql
-- Warehouse architecture:  Source files -> project_staging -> project_dw -> project_reporting
CREATE SCHEMA IF NOT EXISTS project_staging;   -- raw landing tables and cleaned staging tables
CREATE SCHEMA IF NOT EXISTS project_dw;        -- dimensional model (dimensions, facts, audit, data quality)
CREATE SCHEMA IF NOT EXISTS project_reporting; -- views used by the BI tool

COMMENT ON SCHEMA project_staging   IS 'Landing (raw_*) and cleaned (stg_*) copies of the four source files';
COMMENT ON SCHEMA project_dw        IS 'Star schema: dim_*, fact_*, etl_audit_log, dq_results';
COMMENT ON SCHEMA project_reporting IS 'Business-friendly reporting views for Power BI / Tableau';
