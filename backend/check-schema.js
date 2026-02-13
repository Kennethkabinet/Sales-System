const pool = require('./db');

async function check() {
  try {
    // Check sheets columns
    const cols = await pool.query(
      "SELECT column_name FROM information_schema.columns WHERE table_name = 'sheets' ORDER BY ordinal_position"
    );
    console.log('Sheets columns:', cols.rows.map(r => r.column_name));

    // Check if sheet_locks table exists
    const locks = await pool.query(
      "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sheet_locks')"
    );
    console.log('sheet_locks table exists:', locks.rows[0].exists);

    // Check if sheet_edit_sessions table exists
    const sessions = await pool.query(
      "SELECT EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sheet_edit_sessions')"
    );
    console.log('sheet_edit_sessions table exists:', sessions.rows[0].exists);

  } catch (e) {
    console.error('Error:', e.message);
  } finally {
    process.exit(0);
  }
}

check();
