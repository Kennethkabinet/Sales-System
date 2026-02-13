-- Sales & Inventory Management System - Database Schema
-- PostgreSQL Database Schema

-- Enable UUID extension for unique identifiers
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- =============================================================================
-- DEPARTMENTS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS departments (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL UNIQUE,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert default departments
INSERT INTO departments (name, description) VALUES 
    ('Admin', 'System Administration'),
    ('Sales', 'Sales Department'),
    ('Operations', 'Operations Department'),
    ('Finance', 'Finance Department'),
    ('Inventory', 'Inventory Management')
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- ROLES TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS roles (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL UNIQUE,
    description TEXT,
    permissions JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert default roles
INSERT INTO roles (name, description, permissions) VALUES 
    ('admin', 'Full system access', '{"all": true}'),
    ('user', 'Standard user access', '{"read": true, "write": true, "delete": false}'),
    ('viewer', 'Read-only access', '{"read": true, "write": false, "delete": false}')
ON CONFLICT (name) DO NOTHING;

-- =============================================================================
-- USERS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username VARCHAR(50) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(100),
    role_id INTEGER REFERENCES roles(id) DEFAULT 2,
    department_id INTEGER REFERENCES departments(id),
    is_active BOOLEAN DEFAULT TRUE,
    last_login TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create index for faster lookups
CREATE INDEX IF NOT EXISTS idx_users_username ON users(username);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_department ON users(department_id);

-- =============================================================================
-- FILES TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS files (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4() UNIQUE,
    name VARCHAR(255) NOT NULL,
    original_filename VARCHAR(255),
    file_path TEXT,  -- Path on NAS/File Server
    file_type VARCHAR(50) DEFAULT 'xlsx',
    department_id INTEGER REFERENCES departments(id),
    created_by INTEGER REFERENCES users(id),
    current_version INTEGER DEFAULT 1,
    column_mapping JSONB DEFAULT '{}',
    columns JSONB DEFAULT '[]',
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_files_department ON files(department_id);
CREATE INDEX IF NOT EXISTS idx_files_created_by ON files(created_by);

-- =============================================================================
-- FILE VERSIONS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS file_versions (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    file_path TEXT,  -- Path to versioned file on storage
    changes_summary TEXT,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_file_versions_file ON file_versions(file_id);

-- =============================================================================
-- FILE DATA TABLE (Stores imported Excel data)
-- =============================================================================
CREATE TABLE IF NOT EXISTS file_data (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    row_number INTEGER NOT NULL,
    data JSONB NOT NULL,  -- Row data as JSON
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_id, row_number)
);

CREATE INDEX IF NOT EXISTS idx_file_data_file ON file_data(file_id);
CREATE INDEX IF NOT EXISTS idx_file_data_row ON file_data(file_id, row_number);

-- =============================================================================
-- ROW LOCKS TABLE (For real-time collaboration)
-- =============================================================================
CREATE TABLE IF NOT EXISTS row_locks (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    row_id INTEGER REFERENCES file_data(id) ON DELETE CASCADE,
    locked_by INTEGER REFERENCES users(id) ON DELETE CASCADE,
    locked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '5 minutes'),
    UNIQUE(file_id, row_id)
);

CREATE INDEX IF NOT EXISTS idx_row_locks_file ON row_locks(file_id);
CREATE INDEX IF NOT EXISTS idx_row_locks_user ON row_locks(locked_by);

-- =============================================================================
-- FORMULAS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS formulas (
    id SERIAL PRIMARY KEY,
    uuid UUID DEFAULT uuid_generate_v4() UNIQUE,
    name VARCHAR(100) NOT NULL,
    description TEXT,
    expression TEXT NOT NULL,  -- Formula expression
    input_columns JSONB DEFAULT '[]',
    output_column VARCHAR(100) NOT NULL,
    department_id INTEGER REFERENCES departments(id),
    created_by INTEGER REFERENCES users(id),
    is_shared BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    version INTEGER DEFAULT 1,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_formulas_department ON formulas(department_id);
CREATE INDEX IF NOT EXISTS idx_formulas_created_by ON formulas(created_by);

-- =============================================================================
-- FORMULA VERSIONS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS formula_versions (
    id SERIAL PRIMARY KEY,
    formula_id INTEGER REFERENCES formulas(id) ON DELETE CASCADE,
    version_number INTEGER NOT NULL,
    expression TEXT NOT NULL,
    input_columns JSONB DEFAULT '[]',
    output_column VARCHAR(100) NOT NULL,
    created_by INTEGER REFERENCES users(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(formula_id, version_number)
);

-- =============================================================================
-- APPLIED FORMULAS TABLE (Track which formulas are applied to which files)
-- =============================================================================
CREATE TABLE IF NOT EXISTS applied_formulas (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    formula_id INTEGER REFERENCES formulas(id) ON DELETE CASCADE,
    column_mapping JSONB DEFAULT '{}',  -- Maps formula columns to file columns
    applied_by INTEGER REFERENCES users(id),
    applied_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_id, formula_id)
);

-- =============================================================================
-- AUDIT LOGS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS audit_logs (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id),
    action VARCHAR(50) NOT NULL,  -- CREATE, UPDATE, DELETE, LOGIN, etc.
    entity_type VARCHAR(50) NOT NULL,  -- users, files, file_data, formulas
    entity_id INTEGER,
    file_id INTEGER REFERENCES files(id) ON DELETE SET NULL,
    row_number INTEGER,
    field_name VARCHAR(100),
    old_value TEXT,
    new_value TEXT,
    metadata JSONB DEFAULT '{}',  -- Additional context
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_audit_user ON audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_action ON audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_audit_file ON audit_logs(file_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_logs(created_at);

-- =============================================================================
-- FILE PERMISSIONS TABLE (Fine-grained access control)
-- =============================================================================
CREATE TABLE IF NOT EXISTS file_permissions (
    id SERIAL PRIMARY KEY,
    file_id INTEGER REFERENCES files(id) ON DELETE CASCADE,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    permission_level VARCHAR(20) NOT NULL DEFAULT 'read',  -- read, write, admin
    granted_by INTEGER REFERENCES users(id),
    granted_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(file_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_file_permissions_file ON file_permissions(file_id);
CREATE INDEX IF NOT EXISTS idx_file_permissions_user ON file_permissions(user_id);

-- =============================================================================
-- USER SESSIONS TABLE (For tracking active sessions)
-- =============================================================================
CREATE TABLE IF NOT EXISTS user_sessions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
    token_hash VARCHAR(255) NOT NULL,
    device_info TEXT,
    ip_address INET,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    last_activity TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sessions_user ON user_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_token ON user_sessions(token_hash);

-- =============================================================================
-- DASHBOARD CACHE TABLE (For pre-computed statistics)
-- =============================================================================
CREATE TABLE IF NOT EXISTS dashboard_cache (
    id SERIAL PRIMARY KEY,
    cache_key VARCHAR(100) NOT NULL UNIQUE,
    data JSONB NOT NULL,
    department_id INTEGER REFERENCES departments(id),
    computed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (CURRENT_TIMESTAMP + INTERVAL '1 hour')
);

-- =============================================================================
-- SHEETS TABLE (Spreadsheet module)
-- =============================================================================
CREATE TABLE IF NOT EXISTS sheets (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    columns JSONB DEFAULT '["A", "B", "C", "D", "E"]',
    created_by INTEGER REFERENCES users(id),
    department_id INTEGER REFERENCES departments(id),
    is_shared BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_sheets_created_by ON sheets(created_by);
CREATE INDEX IF NOT EXISTS idx_sheets_department ON sheets(department_id);

-- =============================================================================
-- SHEET DATA TABLE (Spreadsheet row data)
-- =============================================================================
CREATE TABLE IF NOT EXISTS sheet_data (
    id SERIAL PRIMARY KEY,
    sheet_id INTEGER REFERENCES sheets(id) ON DELETE CASCADE,
    row_number INTEGER NOT NULL,
    data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(sheet_id, row_number)
);

CREATE INDEX IF NOT EXISTS idx_sheet_data_sheet ON sheet_data(sheet_id);

-- =============================================================================
-- HELPER FUNCTIONS
-- =============================================================================

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Apply trigger to tables with updated_at column
DROP TRIGGER IF EXISTS update_users_updated_at ON users;
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_files_updated_at ON files;
CREATE TRIGGER update_files_updated_at
    BEFORE UPDATE ON files
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_file_data_updated_at ON file_data;
CREATE TRIGGER update_file_data_updated_at
    BEFORE UPDATE ON file_data
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_formulas_updated_at ON formulas;
CREATE TRIGGER update_formulas_updated_at
    BEFORE UPDATE ON formulas
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_departments_updated_at ON departments;
CREATE TRIGGER update_departments_updated_at
    BEFORE UPDATE ON departments
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to clean up expired row locks
CREATE OR REPLACE FUNCTION cleanup_expired_locks()
RETURNS void AS $$
BEGIN
    DELETE FROM row_locks WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- VIEWS FOR COMMON QUERIES
-- =============================================================================

-- View for user details with role and department
CREATE OR REPLACE VIEW user_details AS
SELECT 
    u.id,
    u.username,
    u.email,
    u.full_name,
    r.name as role_name,
    d.name as department_name,
    u.is_active,
    u.last_login,
    u.created_at
FROM users u
LEFT JOIN roles r ON u.role_id = r.id
LEFT JOIN departments d ON u.department_id = d.id;

-- View for file details
CREATE OR REPLACE VIEW file_details AS
SELECT 
    f.id,
    f.uuid,
    f.name,
    f.original_filename,
    f.file_type,
    d.name as department_name,
    u.username as created_by_username,
    f.current_version,
    f.columns,
    f.is_active,
    f.created_at,
    f.updated_at,
    (SELECT COUNT(*) FROM file_data fd WHERE fd.file_id = f.id) as row_count
FROM files f
LEFT JOIN departments d ON f.department_id = d.id
LEFT JOIN users u ON f.created_by = u.id;

-- View for recent audit logs with details
CREATE OR REPLACE VIEW audit_log_details AS
SELECT 
    al.id,
    al.action,
    al.entity_type,
    al.entity_id,
    u.username,
    f.name as file_name,
    al.row_number,
    al.field_name,
    al.old_value,
    al.new_value,
    al.created_at
FROM audit_logs al
LEFT JOIN users u ON al.user_id = u.id
LEFT JOIN files f ON al.file_id = f.id
ORDER BY al.created_at DESC;

-- =============================================================================
-- INSERT DEFAULT ADMIN USER (password: admin123)
-- =============================================================================
-- Note: In production, change this password immediately
-- Password hash is for 'admin123' using bcrypt
INSERT INTO users (username, email, password_hash, full_name, role_id, department_id, is_active)
VALUES (
    'admin',
    'admin@company.com',
    '$2b$10$3eIVMRm4ey1OIettRo6UnuSa1mLaczycDvusHdFseldt.9GQKsqxe',  -- bcrypt hash for 'admin123'
    'System Administrator',
    1,  -- admin role
    1,  -- admin department
    TRUE
) ON CONFLICT (username) DO NOTHING;

-- =============================================================================
-- SAMPLE DATA FOR TESTING (Optional - Comment out in production)
-- =============================================================================

-- Sample formula
INSERT INTO formulas (name, description, expression, input_columns, output_column, is_shared, created_by)
SELECT 
    'Profit Margin',
    'Calculate profit margin as percentage',
    '((selling_price - cost_price) / selling_price) * 100',
    '["selling_price", "cost_price"]'::jsonb,
    'profit_margin',
    TRUE,
    u.id
FROM users u WHERE u.username = 'admin'
ON CONFLICT DO NOTHING;

INSERT INTO formulas (name, description, expression, input_columns, output_column, is_shared, created_by)
SELECT 
    'Total Calculation',
    'Calculate total from quantity and unit price',
    'quantity * unit_price',
    '["quantity", "unit_price"]'::jsonb,
    'total',
    TRUE,
    u.id
FROM users u WHERE u.username = 'admin'
ON CONFLICT DO NOTHING;

INSERT INTO formulas (name, description, expression, input_columns, output_column, is_shared, created_by)
SELECT 
    'Tax Amount',
    'Calculate 10% tax on subtotal',
    'subtotal * 0.10',
    '["subtotal"]'::jsonb,
    'tax_amount',
    TRUE,
    u.id
FROM users u WHERE u.username = 'admin'
ON CONFLICT DO NOTHING;

-- Grant schema creation confirmation
SELECT 'Database schema created successfully!' as status;
