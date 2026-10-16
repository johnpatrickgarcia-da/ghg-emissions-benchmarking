-- =============================================================================
-- 04_yoy_change.sql
-- GHG Emissions Benchmarking - year-over-year change.
--
-- Creates v_yoy: % change in absolute Scope 1+2 and in intensity vs. the prior year (LAG()).
-- Input: v_intensity from 03_intensity_ranking.sql. Run after 03.
-- =============================================================================

SET client_encoding = 'UTF8';

CREATE OR REPLACE VIEW v_yoy AS

WITH lagged AS
	(
	SELECT
		company_id,
		fiscal_year_end,
		scope12_mt,
		LAG(scope12_mt) OVER (PARTITION BY company_id ORDER BY fiscal_year_end) AS prior_scope12_mt,
		intensity_t_per_jpy_bn,
		LAG(intensity_t_per_jpy_bn) OVER (PARTITION BY company_id ORDER BY fiscal_year_end) AS prior_intensity_t_per_jpy_bn
	FROM v_intensity
	),
joined AS
	(SELECT
		company_id,
		fiscal_year_end,
		scope12_mt,
		prior_scope12_mt,
		ROUND((scope12_mt - prior_scope12_mt) / prior_scope12_mt * 100, 1) AS scope12_change_pct,
		intensity_t_per_jpy_bn,
		prior_intensity_t_per_jpy_bn,
		ROUND((intensity_t_per_jpy_bn - prior_intensity_t_per_jpy_bn) / prior_intensity_t_per_jpy_bn * 100, 1) AS intensity_change_pct
	FROM lagged
	)

SELECT *
FROM joined;