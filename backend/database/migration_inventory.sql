-- =============================================================================
-- INVENTORY MODULE MIGRATION
-- Run this after schema.sql to add the inventory module tables
-- =============================================================================

-- =============================================================================
-- PRODUCT MASTER TABLE
-- Pre-defined product templates with threshold settings
-- =============================================================================
CREATE TABLE IF NOT EXISTS product_master (
    id SERIAL PRIMARY KEY,
    product_name VARCHAR(255) NOT NULL,
    qc_code VARCHAR(100),
    maintaining_qty INTEGER NOT NULL DEFAULT 0,   -- Minimum recommended stock
    critical_qty INTEGER NOT NULL DEFAULT 0,       -- Critical alert threshold
    is_active BOOLEAN DEFAULT TRUE,
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_product_master_name ON product_master(product_name);
CREATE INDEX IF NOT EXISTS idx_product_master_active ON product_master(is_active);
CREATE INDEX IF NOT EXISTS idx_product_master_created_by ON product_master(created_by);

-- =============================================================================
-- INVENTORY TRANSACTIONS TABLE
-- Daily IN / OUT movements per product
-- =============================================================================
CREATE TABLE IF NOT EXISTS inventory_transactions (
    id SERIAL PRIMARY KEY,
    product_id INTEGER NOT NULL REFERENCES product_master(id) ON DELETE RESTRICT,
    transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
    qty_in INTEGER NOT NULL DEFAULT 0 CHECK (qty_in >= 0),
    qty_out INTEGER NOT NULL DEFAULT 0 CHECK (qty_out >= 0),
    reference_no VARCHAR(255),       -- PO number, job order, etc.
    remarks TEXT,                    -- Optional notes
    created_by INTEGER REFERENCES users(id),
    updated_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_inv_tx_product ON inventory_transactions(product_id);
CREATE INDEX IF NOT EXISTS idx_inv_tx_date ON inventory_transactions(transaction_date);
CREATE INDEX IF NOT EXISTS idx_inv_tx_product_date ON inventory_transactions(product_id, transaction_date);
CREATE INDEX IF NOT EXISTS idx_inv_tx_created_by ON inventory_transactions(created_by);

-- =============================================================================
-- INVENTORY AUDIT LOG TABLE
-- Track every change to transactions for full audit trail
-- =============================================================================
CREATE TABLE IF NOT EXISTS inventory_audit_log (
    id SERIAL PRIMARY KEY,
    transaction_id INTEGER REFERENCES inventory_transactions(id) ON DELETE SET NULL,
    product_id INTEGER REFERENCES product_master(id) ON DELETE SET NULL,
    action VARCHAR(20) NOT NULL,     -- CREATE, UPDATE, DELETE
    old_data JSONB,
    new_data JSONB,
    performed_by INTEGER REFERENCES users(id),
    performed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_inv_audit_tx ON inventory_audit_log(transaction_id);
CREATE INDEX IF NOT EXISTS idx_inv_audit_product ON inventory_audit_log(product_id);
CREATE INDEX IF NOT EXISTS idx_inv_audit_user ON inventory_audit_log(performed_by);
CREATE INDEX IF NOT EXISTS idx_inv_audit_date ON inventory_audit_log(performed_at);

-- =============================================================================
-- TRIGGERS
-- =============================================================================
DROP TRIGGER IF EXISTS update_product_master_updated_at ON product_master;
CREATE TRIGGER update_product_master_updated_at
    BEFORE UPDATE ON product_master
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_inventory_transactions_updated_at ON inventory_transactions;
CREATE TRIGGER update_inventory_transactions_updated_at
    BEFORE UPDATE ON inventory_transactions
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================================================
-- STOCK SNAPSHOT VIEW
-- Current stock per product = SUM(qty_in) - SUM(qty_out)
-- =============================================================================
CREATE OR REPLACE VIEW product_stock_snapshot AS
SELECT
    p.id,
    p.product_name,
    p.qc_code,
    p.maintaining_qty,
    p.critical_qty,
    p.is_active,
    COALESCE(SUM(t.qty_in), 0)  AS total_in,
    COALESCE(SUM(t.qty_out), 0) AS total_out,
    COALESCE(SUM(t.qty_in), 0) - COALESCE(SUM(t.qty_out), 0) AS current_stock,
    CASE
        WHEN (COALESCE(SUM(t.qty_in), 0) - COALESCE(SUM(t.qty_out), 0)) <= p.critical_qty    THEN 'critical'
        WHEN (COALESCE(SUM(t.qty_in), 0) - COALESCE(SUM(t.qty_out), 0)) <= p.maintaining_qty THEN 'warning'
        ELSE 'ok'
    END AS stock_status
FROM product_master p
LEFT JOIN inventory_transactions t ON p.id = t.product_id
WHERE p.is_active = TRUE
GROUP BY p.id, p.product_name, p.qc_code, p.maintaining_qty, p.critical_qty, p.is_active
ORDER BY p.product_name;

SELECT 'Inventory module migration completed successfully!' AS status;
