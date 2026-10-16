SET client_encoding = 'UTF8';

CREATE OR REPLACE VIEW v_intensity AS

WITH scope12 AS
	(SELECT
		company_id,
		fiscal_year_end,
		MAX(CASE WHEN scope = 'Scope 1' THEN value_mt END) AS scope1_mt,
		MAX(CASE WHEN scope = 'Scope 2 (market-based)' THEN value_mt END) AS scope2_mt,
		MAX(CASE WHEN scope = 'Scope 1' THEN gas_basis END) AS gas_basis
	FROM v_emissions
	GROUP BY company_id, fiscal_year_end
	),
denominators AS
	(SELECT
		company_id,
		fiscal_year_end,
		MAX(CASE WHEN metric = 'Revenue' THEN value_full END) AS revenue_jpy,
		MAX(CASE WHEN metric = 'Headcount' THEN value_full END) AS headcount
	FROM v_operations
	GROUP BY company_id, fiscal_year_end
	),
joined AS
	(SELECT
		s.company_id,
		s.fiscal_year_end,
		s.scope1_mt,
		s.scope2_mt,
		(s.scope1_mt + s.scope2_mt) AS scope12_mt,
		s.gas_basis,
		d.revenue_jpy,
		d.headcount,
		(s.scope1_mt + s.scope2_mt) * 1000000 / (d.revenue_jpy / 1000000000) AS intensity_t_per_jpy_bn,
		(s.scope1_mt + s.scope2_mt) * 1000000 / d.headcount AS intensity_t_per_emp
	FROM scope12 s
	JOIN denominators d
		ON s.company_id = d.company_id
		AND s.fiscal_year_end = d.fiscal_year_end
	)

SELECT
	company_id,
	fiscal_year_end,
	ROUND(scope1_mt, 3) AS scope1_mt,
	ROUND(scope2_mt, 3) AS scope2_mt,
	ROUND(scope12_mt, 3) AS scope12_mt,
	gas_basis,
	ROUND(revenue_jpy) AS revenue_jpy,
	headcount,
	ROUND(intensity_t_per_jpy_bn, 2) AS intensity_t_per_jpy_bn,
	ROUND(intensity_t_per_emp, 2) AS intensity_t_per_emp,
	RANK() OVER (PARTITION BY fiscal_year_end ORDER BY intensity_t_per_jpy_bn) AS rank_by_revenue,
	ROUND(AVG(intensity_t_per_jpy_bn) OVER (PARTITION BY fiscal_year_end), 2) AS peer_avg_t_per_jpy_bn
FROM joined;