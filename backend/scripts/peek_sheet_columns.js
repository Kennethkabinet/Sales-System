/* Peek at how Postgres returns sheets.columns (array vs JSON string). */
require('dotenv').config();
const pool = require('../db');

(async () => {
  const r = await pool.query(
    `SELECT id, name, columns FROM sheets WHERE is_active=TRUE ORDER BY id DESC LIMIT 5`
  );
  console.log('rows:', r.rows.length);
  for (const s of r.rows) {
    console.log('\nSheet', s.id, '-', s.name);
    console.log('  typeof columns:', typeof s.columns);
    console.log('  isArray:', Array.isArray(s.columns));
    if (typeof s.columns === 'string') {
      console.log('  columns string prefix:', s.columns.slice(0, 80));
    } else {
      try {
        console.log('  columns preview:', JSON.stringify(s.columns).slice(0, 120));
      } catch {
        console.log('  columns preview: <unstringifiable>');
      }
    }
  }
  await pool.end();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
