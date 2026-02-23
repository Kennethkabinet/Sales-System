const pool = require('../db');

async function migrate() {
  try {
    console.log('Starting sheet folders migration...');

    // Add folder_id to sheets table
    await pool.query(`
      ALTER TABLE sheets 
      ADD COLUMN IF NOT EXISTS folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL
    `);
    console.log('✓ folder_id column added to sheets table');

    // Create index for better query performance
    await pool.query(`
      CREATE INDEX IF NOT EXISTS idx_sheets_folder ON sheets(folder_id)
    `);
    console.log('✓ sheets folder_id index created');

    console.log('Migration complete!');
    process.exit(0);
  } catch (err) {
    console.error('Migration error:', err);
    process.exit(1);
  }
}

migrate();
