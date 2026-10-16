-- =============================================================================
-- 05_scope3_checks.sql
-- GHG Emissions Benchmarking - Scope 3 reconciliation and category counts.
--
-- Creates v_scope3_summary: sum of categories vs. reported Scope 3 total, categories
-- reported (including a reported 0) and Category 11 share of the reported total.
-- completeness_pct (count / 15) is an intermediate check, hidden in the model.
-- Input: v_scope3, v_emissions from 02_standardize.sql. Run after 02.
-- =============================================================================

SET client_encoding = 'UTF8';

CREATE OR REPLACE VIEW v_scope3_summary AS

WITH categories AS 
	(SELECT
		company_id,
		fiscal_year_end,
		SUM(value_mt) AS sum_of_categories_mt,
		SUM(CASE WHEN disclosed = 'Yes' THEN 1 ELSE 0 END) AS categories_disclosed,
		MAX(CASE WHEN category_no = 11 THEN value_mt END) AS cat11_mt
	FROM v_scope3
	GROUP BY
		company_id,
		fiscal_year_end)
SELECT
	c.company_id,
	c.fiscal_year_end,
	e.value_mt AS reported_total_mt,
	c.sum_of_categories_mt,
	e.value_mt - c.sum_of_categories_mt AS difference_mt,
	c.categories_disclosed,
	ROUND(c.categories_disclosed / 15.0 * 100, 1) AS completeness_pct,
	ROUND(c.cat11_mt / e.value_mt * 100, 1) AS cat11_share_pct
FROM categories c
JOIN v_emissions e
	ON c.company_id = e.company_id
	AND c.fiscal_year_end = e.fiscal_year_end
	AND e.scope = 'Scope 3 Total';