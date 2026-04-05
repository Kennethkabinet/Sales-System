-- =============================================================================
-- SHEET DATA VIEWS (Columnized access to JSONB)
--
-- Apply this migration to an existing database if you want to query sheet rows
-- with separate SQL columns instead of a single JSONB `sheet_data.data` column.
--
-- Safe to run multiple times (uses CREATE OR REPLACE VIEW).
-- =============================================================================

-- Generic key/value representation of sheet row data
CREATE OR REPLACE VIEW sheet_data_kv AS
SELECT
    sd.id AS sheet_data_id,
    sd.sheet_id,
    sd.row_number,
    kv.key AS column_name,
    kv.value AS cell_value,
    sd.created_at,
    sd.updated_at
FROM sheet_data sd
CROSS JOIN LATERAL jsonb_each_text(COALESCE(sd.data, '{}'::jsonb)) AS kv(key, value);

-- Inventory Tracker: expose common fields as separate SQL columns
CREATE OR REPLACE VIEW inventory_tracker_rows AS
WITH inv_keys AS (
    SELECT
        s.id AS sheet_id,
        (SELECT c
         FROM jsonb_array_elements_text(COALESCE(s.columns, '[]'::jsonb)) AS c
         WHERE c LIKE 'INV:product_name|%'
         LIMIT 1) AS inv_product_key,
        (SELECT c
         FROM jsonb_array_elements_text(COALESCE(s.columns, '[]'::jsonb)) AS c
         WHERE c LIKE 'INV:code|%'
         LIMIT 1) AS inv_code_key
    FROM sheets s
)
SELECT
    sd.id AS sheet_data_id,
    sd.sheet_id,
    s.name AS sheet_name,
    sd.row_number,
    COALESCE(
        NULLIF(sd.data->>'Material Name', ''),
        NULLIF(sd.data->>'Product Name', ''),
        NULLIF(sd.data->>ik.inv_product_key, '')
    ) AS material_name,
    COALESCE(
        NULLIF(sd.data->>'QB Code', ''),
        NULLIF(sd.data->>'QC Code', ''),
        NULLIF(sd.data->>ik.inv_code_key, '')
    ) AS qb_code,
    sd.data->>'Stock' AS stock_text,
    CASE
        WHEN NULLIF(sd.data->>'Stock', '') ~ '^[+-]?[0-9]+([.][0-9]+)?$' THEN (sd.data->>'Stock')::numeric
        ELSE NULL
    END AS stock_num,
    sd.data->>'Maintaining Qty' AS maintaining_qty,
    sd.data->>'Maintaining Unit' AS maintaining_unit,
    sd.data->>'Maintaining' AS maintaining_legacy,
    sd.data->>'Critical' AS critical_text,
    CASE
        WHEN NULLIF(sd.data->>'Critical', '') ~ '^[+-]?[0-9]+([.][0-9]+)?$' THEN (sd.data->>'Critical')::numeric
        ELSE NULL
    END AS critical_num,
    sd.data->>'Total Quantity' AS total_quantity_text,
    CASE
        WHEN NULLIF(sd.data->>'Total Quantity', '') ~ '^[+-]?[0-9]+([.][0-9]+)?$' THEN (sd.data->>'Total Quantity')::numeric
        ELSE NULL
    END AS total_quantity_num,
    sd.data AS raw_data,
    sd.created_at,
    sd.updated_at
FROM sheet_data sd
JOIN sheets s ON s.id = sd.sheet_id
LEFT JOIN inv_keys ik ON ik.sheet_id = s.id
WHERE
    s.is_active = TRUE
    AND (s.columns ? 'Stock')
    AND (s.columns ? 'Total Quantity')
    AND (
        (s.columns ? 'Material Name')
        OR (s.columns ? 'Product Name')
        OR (ik.inv_product_key IS NOT NULL)
    )
    AND (
        (s.columns ? 'QB Code')
        OR (s.columns ? 'QC Code')
        OR (ik.inv_code_key IS NOT NULL)
    );
