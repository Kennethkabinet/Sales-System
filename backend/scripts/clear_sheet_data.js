#!/usr/bin/env node

const pool = require('../db');

function parseArgs(argv) {
  const out = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--sheet-id') out.sheetId = parseInt(argv[++i], 10);
    else if (a === '--sheet-name') out.sheetName = argv[++i];
    else if (a === '--dry-run') out.dryRun = true;
    else if (a === '-h' || a === '--help') out.help = true;
  }
  return out;
}

function usage() {
  return `
Usage:
  node scripts/clear_sheet_data.js --sheet-id <id> [--dry-run]
  node scripts/clear_sheet_data.js --sheet-name "March Inventory" [--dry-run]

What it does:
  - Deletes all rows from sheet_data for the sheet
  - Deletes all rows from file_data for any linked files (files.source_sheet_id = sheet)
  - Does NOT delete the sheet itself
`;
}

(async () => {
  const args = parseArgs(process.argv.slice(2));
  if (args.help || (!args.sheetId && !args.sheetName)) {
    console.log(usage());
    process.exit(args.help ? 0 : 2);
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    let sheetRow;
    if (Number.isFinite(args.sheetId)) {
      const res = await client.query(
        'SELECT id, name FROM sheets WHERE id = $1 AND is_active = TRUE',
        [args.sheetId]
      );
      sheetRow = res.rows[0];
    } else {
      const res = await client.query(
        'SELECT id, name FROM sheets WHERE name = $1 AND is_active = TRUE ORDER BY id DESC LIMIT 1',
        [args.sheetName]
      );
      sheetRow = res.rows[0];
    }

    if (!sheetRow) {
      throw new Error('Sheet not found (or inactive).');
    }

    const sheetId = sheetRow.id;

    const linkedFiles = await client.query(
      'SELECT id, name FROM files WHERE source_sheet_id = $1 AND is_active = TRUE',
      [sheetId]
    );

    const sheetCountRes = await client.query(
      'SELECT COUNT(*)::int AS cnt FROM sheet_data WHERE sheet_id = $1',
      [sheetId]
    );

    const fileIds = linkedFiles.rows.map((r) => r.id);
    let fileDataCount = 0;
    if (fileIds.length) {
      const fileCountRes = await client.query(
        'SELECT COUNT(*)::int AS cnt FROM file_data WHERE file_id = ANY($1)',
        [fileIds]
      );
      fileDataCount = fileCountRes.rows[0]?.cnt ?? 0;
    }

    console.log(`Target sheet: #${sheetId} "${sheetRow.name}"`);
    console.log(`sheet_data rows: ${sheetCountRes.rows[0]?.cnt ?? 0}`);
    console.log(`linked files: ${fileIds.length}`);
    console.log(`linked file_data rows: ${fileDataCount}`);

    if (args.dryRun) {
      console.log('Dry run; no changes applied.');
      await client.query('ROLLBACK');
      process.exit(0);
    }

    await client.query('DELETE FROM sheet_data WHERE sheet_id = $1', [sheetId]);

    if (fileIds.length) {
      await client.query('DELETE FROM file_data WHERE file_id = ANY($1)', [fileIds]);
      await client.query(
        'UPDATE files SET updated_at = CURRENT_TIMESTAMP WHERE id = ANY($1)',
        [fileIds]
      );
    }

    await client.query(
      'UPDATE sheets SET updated_at = CURRENT_TIMESTAMP WHERE id = $1',
      [sheetId]
    );

    await client.query('COMMIT');
    console.log('Done: cleared sheet_data (and linked file_data).');
  } catch (e) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {}
    console.error('Failed:', e?.message || e);
    process.exit(1);
  } finally {
    client.release();
    await pool.end().catch(() => {});
  }
})();
