const fs = require('fs');
const path = require('path');
const pool = require('./db');

async function runMigration() {
  try {
    console.log('Reading migration file...');
    const migrationSQL = fs.readFileSync(
      path.join(__dirname, 'database', 'migration_user_module.sql'),
      'utf8'
    );

    console.log('Executing migration...');
    await pool.query(migrationSQL);
    
    console.log('✅ Migration completed successfully!');
    
    // Verify the changes
    const rolesResult = await pool.query('SELECT name FROM roles ORDER BY name');
    console.log('\nAvailable roles:', rolesResult.rows.map(r => r.name).join(', '));
    
    const columnsResult = await pool.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'users' 
      AND column_name IN ('created_by', 'deactivated_at', 'deactivated_by')
    `);
    console.log('New user columns added:', columnsResult.rows.map(r => r.column_name).join(', '));
    
    const sheetsResult = await pool.query(`
      SELECT column_name 
      FROM information_schema.columns 
      WHERE table_name = 'sheets' 
      AND column_name = 'last_edited_by'
    `);
    console.log('New sheets column:', sheetsResult.rows.map(r => r.column_name).join(', '));
    
    const tablesResult = await pool.query(`
      SELECT table_name 
      FROM information_schema.tables 
      WHERE table_name = 'sheet_edit_history' 
      AND table_schema = 'public'
    `);
    console.log('New table created:', tablesResult.rows.map(r => r.table_name).join(', '));
    
    await pool.end();
    process.exit(0);
  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    console.error(error);
    await pool.end();
    process.exit(1);
  }
}

runMigration();
