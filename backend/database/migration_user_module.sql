-- Migration Script: User Module & Sheet Edit Tracking
-- This migration adds the User Management Module and Sheet Edit Tracking features
-- Run this after the initial schema has been set up

-- =============================================================================
-- ADD EDITOR ROLE
-- =============================================================================
INSERT INTO roles (name, description, permissions) VALUES 
    ('editor', 'Editor with full sheet edit access', '{"read": true, "write": true, "delete": true}')
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- UPDATE USERS TABLE - Add user management fields
-- =============================================================================
-- Add new columns if they don't exist
ALTER TABLE users ADD COLUMN IF NOT EXISTS deactivated_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE users ADD COLUMN IF NOT EXISTS deactivated_by INTEGER REFERENCES users(id);
ALTER TABLE users ADD COLUMN IF NOT EXISTS created_by INTEGER REFERENCES users(id);

-- =============================================================================
-- UPDATE SHEETS TABLE - Add edit tracking
-- =============================================================================
ALTER TABLE sheets ADD COLUMN IF NOT EXISTS last_edited_by INTEGER REFERENCES users(id);

-- =============================================================================
-- CREATE SHEET EDIT HISTORY TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS sheet_edit_history (
    id SERIAL PRIMARY KEY,
    sheet_id INTEGER REFERENCES sheets(id) ON DELETE CASCADE,
    row_number INTEGER,
    column_name VARCHAR(100),
    old_value TEXT,
    new_value TEXT,
    edited_by INTEGER REFERENCES users(id),
    edited_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    action VARCHAR(50) NOT NULL  -- INSERT, UPDATE, DELETE, RENAME_COLUMN, RENAME_ROW
);

CREATE INDEX IF NOT EXISTS idx_sheet_edit_history_sheet ON sheet_edit_history(sheet_id);
CREATE INDEX IF NOT EXISTS idx_sheet_edit_history_user ON sheet_edit_history(edited_by);
CREATE INDEX IF NOT EXISTS idx_sheet_edit_history_date ON sheet_edit_history(edited_at);

-- =============================================================================
-- VERIFY MIGRATION
-- =============================================================================
SELECT 'Migration completed successfully!' as status;

-- Show updated roles
SELECT 'Available Roles:' as info;
SELECT id, name, description FROM roles ORDER BY id;

-- Show new columns in users table
SELECT 'Users Table Columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'users' 
AND column_name IN ('deactivated_at', 'deactivated_by', 'created_by')
ORDER BY column_name;

-- Show new columns in sheets table
SELECT 'Sheets Table Columns:' as info;
SELECT column_name, data_type 
FROM information_schema.columns 
WHERE table_name = 'sheets' 
AND column_name = 'last_edited_by';

-- Show sheet_edit_history table
SELECT 'Sheet Edit History Table:' as info;
SELECT EXISTS (
   SELECT FROM information_schema.tables 
   WHERE table_name = 'sheet_edit_history'
) as table_exists;
