const pool = require('../db');

async function migrate() {
  try {
    // Create folders table
    await pool.query(
      "CREATE TABLE IF NOT EXISTS folders (" +
      "  id SERIAL PRIMARY KEY," +
      "  name VARCHAR(255) NOT NULL," +
      "  parent_id INTEGER REFERENCES folders(id) ON DELETE CASCADE," +
      "  created_by INTEGER REFERENCES users(id)," +
      "  is_active BOOLEAN DEFAULT TRUE," +
      "  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP," +
      "  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP" +
      ")"
    );
    console.log('folders table created');

    await pool.query("CREATE INDEX IF NOT EXISTS idx_folders_parent ON folders(parent_id)");
    await pool.query("CREATE INDEX IF NOT EXISTS idx_folders_user ON folders(created_by)");
    console.log('folders indexes created');

    // Add folder_id to files
    await pool.query("ALTER TABLE files ADD COLUMN IF NOT EXISTS folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL");
    console.log('folder_id column added to files');

    // Add source_sheet_id to files  
    await pool.query("ALTER TABLE files ADD COLUMN IF NOT EXISTS source_sheet_id INTEGER REFERENCES sheets(id) ON DELETE SET NULL");
    console.log('source_sheet_id column added to files');

    await pool.query("CREATE INDEX IF NOT EXISTS idx_files_folder ON files(folder_id)");
    console.log('files folder index created');

    console.log('Migration complete!');
    process.exit(0);
  } catch (err) {
    console.error('Migration error:', err);
    process.exit(1);
  }
}

migrate();
