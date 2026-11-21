-- 00_create_database.sql
-- Run once as a superuser, for example:  psql -U postgres -f sql/00_create_database.sql
-- The Python pipeline (etl/etl_pipeline.py) does this automatically if the database is missing.
CREATE DATABASE fraud_dw ENCODING 'UTF8';
