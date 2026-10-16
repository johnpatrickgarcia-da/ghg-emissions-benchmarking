-- =============================================================================
-- 01_create_tables.sql
-- GHG Emissions Benchmarking — create the five tables and load the CSVs.
--
-- Run in psql (or pgAdmin's PSQL Tool), connected to ghg_emissions_benchmarking,
-- from the repository root:
--
--     \cd 'path/to/ghg-emissions-benchmarking'
--     \i sql/01_create_tables.sql
--
-- psql is needed because \copy reads the CSVs as you, not as the PostgreSQL
-- service account. The script is safe to rerun: it drops and rebuilds everything.
-- Input: data/csv/*.csv, produced by scripts/export_csv.py.
-- =============================================================================

SET client_encoding = 'UTF8';  -- Windows psql defaults to WIN1252, which cannot display subscript 2

\set ON_ERROR_STOP on

BEGIN;

-- Drop in reverse dependency order so the script can be rerun.
-- CASCADE also drops the views from 02_standardize.sql; rerun 02 afterwards.
DROP TABLE IF EXISTS operations CASCADE;
DROP TABLE IF EXISTS scope3 CASCADE;
DROP TABLE IF EXISTS emissions CASCADE;
DROP TABLE IF EXISTS units CASCADE;
DROP TABLE IF EXISTS fundamentals CASCADE;

-- -----------------------------------------------------------------------------
-- fundamentals: one row per company
-- -----------------------------------------------------------------------------
CREATE TABLE fundamentals (
    company_id         text PRIMARY KEY,
    company_name       text NOT NULL,
    ticker             text NOT NULL,
    country            text NOT NULL,
    currency           text NOT NULL,
    sector             text NOT NULL,
    gics_sub_industry  text NOT NULL,
    fiscal_year_end    date NOT NULL
);

-- -----------------------------------------------------------------------------
-- units: every reported emissions unit and its conversion to million t-CO₂e
-- -----------------------------------------------------------------------------
CREATE TABLE units (
    unit_reported      text PRIMARY KEY,
    unit_standard      text NOT NULL,
    conversion_factor  numeric,            -- NULL for the 'N/A' unit
    notes              text,
    CHECK ((unit_reported = 'N/A') = (conversion_factor IS NULL))
);

-- -----------------------------------------------------------------------------
-- emissions: Scope 1, Scope 2 (market- and location-based), Scope 3 total
-- -----------------------------------------------------------------------------
CREATE TABLE emissions (
    company_id         text NOT NULL REFERENCES fundamentals (company_id),
    fiscal_year_end    date NOT NULL,
    scope              text NOT NULL CHECK (scope IN
                         ('Scope 1', 'Scope 2 (market-based)',
                          'Scope 2 (location-based)', 'Scope 3 Total')),
    disclosed          text NOT NULL CHECK (disclosed IN ('Yes', 'No')),
    value_reported     numeric,            -- NULL when not disclosed
    unit_reported      text NOT NULL REFERENCES units (unit_reported),
    boundary_method    text NOT NULL CHECK (boundary_method IN
                         ('Operational control', 'Financial control',
                          'Equity share', 'Not Stated', 'N/A')),
    assurance_status   text NOT NULL CHECK (assurance_status IN
                         ('Limited Assurance', 'Reasonable Assurance',
                          'No Assurance', 'N/A')),
    source_document    text,
    source_page        integer,
    methodology_notes  text,
    assurance_notes    text,
    notes              text,
    PRIMARY KEY (company_id, fiscal_year_end, scope),
    -- a disclosed row must have a value; an undisclosed row must not
    CHECK ((disclosed = 'Yes') = (value_reported IS NOT NULL))
);

-- -----------------------------------------------------------------------------
-- scope3: the 15 GHG Protocol Scope 3 categories
-- -----------------------------------------------------------------------------
CREATE TABLE scope3 (
    company_id         text NOT NULL REFERENCES fundamentals (company_id),
    fiscal_year_end    date NOT NULL,
    category_no        integer NOT NULL CHECK (category_no BETWEEN 1 AND 15),
    category_name      text NOT NULL,
    disclosed          text NOT NULL CHECK (disclosed IN ('Yes', 'No')),
    value_reported     numeric,
    unit_reported      text NOT NULL REFERENCES units (unit_reported),
    boundary_method    text NOT NULL CHECK (boundary_method IN
                         ('Operational control', 'Financial control',
                          'Equity share', 'Not Stated', 'N/A')),
    assurance_status   text NOT NULL CHECK (assurance_status IN
                         ('Limited Assurance', 'Reasonable Assurance',
                          'No Assurance', 'N/A')),
    source_document    text,
    source_page        integer,
    methodology_notes  text,
    assurance_notes    text,
    notes              text,
    PRIMARY KEY (company_id, fiscal_year_end, category_no),
    CHECK ((disclosed = 'Yes') = (value_reported IS NOT NULL))
);

-- -----------------------------------------------------------------------------
-- operations: revenue, exchange rate, headcount, units sold
-- Full value = value_reported * unit_scale
-- -----------------------------------------------------------------------------
CREATE TABLE operations (
    company_id         text NOT NULL REFERENCES fundamentals (company_id),
    fiscal_year_end    date NOT NULL,
    metric             text NOT NULL CHECK (metric IN
                         ('Revenue', 'JPY to USD Exchange Rate',
                          'Headcount', 'Units sold')),
    value_reported     numeric NOT NULL,
    unit_label         text NOT NULL,
    unit_scale         numeric NOT NULL CHECK (unit_scale > 0),
    source_document    text NOT NULL,
    source_page        integer,
    methodology_notes  text,
    notes              text,
    PRIMARY KEY (company_id, fiscal_year_end, metric)
);

-- -----------------------------------------------------------------------------
-- Load. Parent tables first, so the foreign keys can be checked.
-- Empty fields load as NULL (the export writes numeric 'N/A' as empty).
-- -----------------------------------------------------------------------------
\copy fundamentals FROM 'data/csv/fundamentals.csv' WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy units        FROM 'data/csv/units.csv'        WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy emissions    FROM 'data/csv/emissions.csv'    WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy scope3       FROM 'data/csv/scope3.csv'       WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')
\copy operations   FROM 'data/csv/operations.csv'   WITH (FORMAT csv, HEADER true, ENCODING 'UTF8')

COMMIT;

-- -----------------------------------------------------------------------------
-- Check: rows loaded per company and table.
-- Expected per company: emissions 12, scope3 45, operations 12.
-- -----------------------------------------------------------------------------
SELECT f.company_id,
       (SELECT count(*) FROM emissions  e WHERE e.company_id = f.company_id) AS emissions_rows,
       (SELECT count(*) FROM scope3     s WHERE s.company_id = f.company_id) AS scope3_rows,
       (SELECT count(*) FROM operations o WHERE o.company_id = f.company_id) AS operations_rows
FROM fundamentals f
ORDER BY f.company_id;
