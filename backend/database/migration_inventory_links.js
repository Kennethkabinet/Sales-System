const pool = require('../db');

async function migrate() {
  try {
    console.log('Starting inventory links + production lines migration...');

    await pool.query(`
      CREATE TABLE IF NOT EXISTS sheet_links (
        id SERIAL PRIMARY KEY,
        link_id UUID DEFAULT uuid_generate_v4() UNIQUE,
        source_sheet_id INTEGER NOT NULL REFERENCES sheets(id) ON DELETE CASCADE,
        target_sheet_id INTEGER NOT NULL REFERENCES sheets(id) ON DELETE CASCADE,
        link_type VARCHAR(50) NOT NULL,
        column_mapping JSONB DEFAULT '{}'::jsonb,
        enabled BOOLEAN DEFAULT TRUE,
        created_by INTEGER REFERENCES users(id),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        CONSTRAINT chk_sheet_link_type CHECK (link_type IN ('INBOUND_SUPPLIER', 'OUTBOUND_PRODUCTION')),
        CONSTRAINT chk_sheet_link_source_target CHECK (source_sheet_id <> target_sheet_id),
        UNIQUE(source_sheet_id, target_sheet_id, link_type)
      );

      CREATE INDEX IF NOT EXISTS idx_sheet_links_source ON sheet_links(source_sheet_id);
      CREATE INDEX IF NOT EXISTS idx_sheet_links_target ON sheet_links(target_sheet_id);
    `);
    console.log('✓ sheet_links table and indexes ready');

    await pool.query(`
      CREATE TABLE IF NOT EXISTS production_lines (
        id SERIAL PRIMARY KEY,
        name VARCHAR(150) NOT NULL UNIQUE,
        description TEXT,
        is_active BOOLEAN DEFAULT TRUE,
        created_by INTEGER REFERENCES users(id),
        updated_by INTEGER REFERENCES users(id),
        created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
      );

      CREATE INDEX IF NOT EXISTS idx_production_lines_active ON production_lines(is_active);
    `);
    console.log('✓ production_lines table and indexes ready');

    console.log('Migration complete!');
    process.exit(0);
  } catch (error) {
    console.error('Migration error:', error);
    process.exit(1);
  }
}

migrate();
