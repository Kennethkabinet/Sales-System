/* Print row counts for core tables to confirm which DB the backend is connected to. */
const pool = require('../db');

(async () => {
  const tables = ['sheets', 'sheet_data', 'files', 'file_data', 'users'];
  for (const t of tables) {
    try {
      const r = await pool.query(`SELECT COUNT(*)::int AS cnt FROM ${t}`);
      console.log(`${t}: ${r.rows[0].cnt}`);
    } catch (e) {
      console.log(`${t}: ERROR ${e.message}`);
    }
  }
  await pool.end();
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
