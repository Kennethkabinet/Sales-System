-- =============================================================================
-- CLEANUP SCRIPT - Remove Discrepancy Feature from Database
-- Run this to remove all discrepancy-related tables, views, and data
-- =============================================================================

-- Drop the view first (depends on table)
DROP VIEW IF EXISTS products_with_discrepancies CASCADE;

-- Drop the table
DROP TABLE IF EXISTS inventory_discrepancies CASCADE;

SELECT 'Discrepancy feature successfully removed from database!' AS status;
