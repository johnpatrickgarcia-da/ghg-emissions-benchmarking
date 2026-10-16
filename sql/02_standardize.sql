SET client_encoding = 'UTF8';

CREATE OR REPLACE VIEW v_emissions AS
SELECT 
	company_id, 
	fiscal_year_end, 
	scope, 
	disclosed, 
	value_reported, 
	e.unit_reported, 
	value_reported * conversion_factor AS value_mt, 
	CASE	
		WHEN e.unit_reported LIKE '%CO₂' THEN 'CO₂'
		WHEN e.unit_reported LIKE '%e' THEN 'CO₂e'
		ELSE NULL
	END AS gas_basis, 
	boundary_method,
	assurance_status, 
	source_document, 
	source_page, 
	methodology_notes, 
	assurance_notes
FROM emissions e
JOIN units u ON e.unit_reported = u.unit_reported;

CREATE OR REPLACE VIEW v_scope3 AS
SELECT
	company_id, 
	fiscal_year_end, 
	category_no,
	category_name,
	disclosed, 
	value_reported, 
	s.unit_reported, 
	value_reported * conversion_factor AS value_mt, 
	CASE	
		WHEN s.unit_reported LIKE '%CO₂' THEN 'CO₂'
		WHEN s.unit_reported LIKE '%e' THEN 'CO₂e'
		ELSE NULL
	END AS gas_basis, 
	boundary_method,
	assurance_status, 
	source_document, 
	source_page, 
	methodology_notes, 
	assurance_notes
FROM scope3 s
JOIN units u ON s.unit_reported = u.unit_reported;

CREATE OR REPLACE VIEW v_operations AS

SELECT
	company_id, 
	fiscal_year_end, 
	metric, 
	value_reported, 
	unit_scale, 
	value_reported * unit_scale AS value_full, 
	unit_label, 
	source_document, 
	source_page, 
	methodology_notes
FROM operations;