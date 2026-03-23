/*
  Remove (clear) Inventory Tracker "Total Quantity" values from Postgres sheet_data.

  This does NOT remove the column from sheets.columns.
  It only removes the per-row JSON value(s) so dashboard aggregation no longer
  sees stale Total Quantity values.

  Supports both legacy and encoded keys:
    - "Total Quantity"
    - "INV:total_qty|Total Quantity" (or any header text after the '|')

  Usage:
    node scripts/remove_total_quantity_values.js --sheet-id 123 --apply
    node scripts/remove_total_quantity_values.js --sheet-name "March Inventory" --apply
    node scripts/remove_total_quantity_values.js --name-like "%Inventory%" --apply --all
    node scripts/remove_total_quantity_values.js --all-inventory --apply

  By default it runs in dry-run mode. Use --apply to actually update.
*/

require('dotenv').config();
const pool = require('../db');

function parseArgs(argv) {
  const out = {
    sheetId: null,
    sheetName: null,
    nameLike: null,
    all: false,
    allInventory: false,
    apply: false,
    help: false,
  };

  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--sheet-id') out.sheetId = parseInt(argv[++i] || '', 10);
    else if (a === '--sheet-name') out.sheetName = argv[++i] || '';
    else if (a === '--name-like') out.nameLike = argv[++i] || '';
    else if (a === '--all') out.all = true;
    else if (a === '--all-inventory') out.allInventory = true;
    else if (a === '--apply') out.apply = true;
    else if (a === '--help' || a === '-h') out.help = true;
  }
  return out;
}

function usage() {
  console.log(
    `\nRemove Total Quantity values (Inventory Tracker)\n\n` +
      `Dry-run (default):\n` +
      `  node scripts/remove_total_quantity_values.js --sheet-name "March Inventory"\n\n` +
      `Apply updates:\n` +
      `  node scripts/remove_total_quantity_values.js --sheet-name "March Inventory" --apply\n` +
      `  node scripts/remove_total_quantity_values.js --sheet-id 123 --apply\n` +
      `  node scripts/remove_total_quantity_values.js --name-like "%Inventory%" --all --apply\n` +
      `  node scripts/remove_total_quantity_values.js --all-inventory --apply\n\n` +
      `Notes:\n` +
      `- Keeps the column; clears only the stored per-row values.\n` +
      `- Handles legacy key "Total Quantity" and encoded key "INV:total_qty|...".\n`
  );
}

function isEncodedTotalQtyCol(col) {
  return typeof col === 'string' && col.startsWith('INV:total_qty|');
}

function resolveTotalQtyKeysFromColumns(columns) {
  const out = [];
  if (Array.isArray(columns)) {
    if (columns.includes('Total Quantity')) out.push('Total Quantity');
    const encoded = columns.find(isEncodedTotalQtyCol);
    if (encoded) out.push(encoded);
  }
  // De-dupe while keeping order
  return Array.from(new Set(out));
}

async function statsForKey(sheetId, key) {
  const sql = `
    SELECT
      COUNT(*)::int AS rows_total,
      COUNT(*) FILTER (WHERE data ? $2)::int AS rows_with_key,
      COUNT(*) FILTER (WHERE (data ? $2) AND NULLIF(BTRIM(COALESCE(data->>$2, '')), '') IS NOT NULL)::int AS rows_with_nonempty,
      SUM((NULLIF(REPLACE((data->>$2), ',', ''), '')::numeric)) AS sum_numeric
    FROM sheet_data
    WHERE sheet_id = $1
  `;
  const r = await pool.query(sql, [sheetId, key]);
  return r.rows?.[0] ?? { rows_total: 0, rows_with_key: 0, rows_with_nonempty: 0, sum_numeric: null };
}

async function sampleValues(sheetId, key, limit = 10) {
  const sql = `
    SELECT row_number, data->>$2 AS value
    FROM sheet_data
    WHERE sheet_id=$1 AND (data ? $2) AND NULLIF(BTRIM(COALESCE(data->>$2, '')), '') IS NOT NULL
    ORDER BY row_number ASC
    LIMIT ${Math.max(1, Math.min(50, limit))}
  `;
  const r = await pool.query(sql, [sheetId, key]);
  return r.rows || [];
}

async function removeKeyValues(sheetId, key) {
  const sql = `
    UPDATE sheet_data
    SET
      data = COALESCE(data, '{}'::jsonb) - $2,
      updated_at = CURRENT_TIMESTAMP
    WHERE sheet_id=$1 AND (data ? $2)
  `;
  const r = await pool.query(sql, [sheetId, key]);
  return r.rowCount || 0;
}

async function findTargetSheets(args) {
  if (Number.isInteger(args.sheetId) && args.sheetId > 0) {
    const r = await pool.query(
      `SELECT id, name, created_at, updated_at, columns FROM sheets WHERE id=$1 AND is_active=TRUE`,
      [args.sheetId]
    );
    return r.rows || [];
  }

  if (args.allInventory) {
    const r = await pool.query(
      `SELECT id, name, created_at, updated_at, columns
       FROM sheets
       WHERE is_active=TRUE
       ORDER BY id DESC`
    );
    const rows = r.rows || [];
    return rows.filter((s) => {
      const cols = Array.isArray(s.columns) ? s.columns : [];
      return cols.includes('Total Quantity') || cols.some(isEncodedTotalQtyCol);
    });
  }

  if ((args.sheetName || '').trim()) {
    const name = (args.sheetName || '').trim();
    const r = await pool.query(
      `SELECT id, name, created_at, updated_at, columns
       FROM sheets
       WHERE name=$1 AND is_active=TRUE
       ORDER BY id DESC`,
      [name]
    );
    return args.all ? (r.rows || []) : (r.rows || []).slice(0, 1);
  }

  if ((args.nameLike || '').trim()) {
    const pattern = (args.nameLike || '').trim();
    const r = await pool.query(
      `SELECT id, name, created_at, updated_at, columns
       FROM sheets
       WHERE is_active=TRUE AND name ILIKE $1
       ORDER BY id DESC`,
      [pattern]
    );
    return args.all ? (r.rows || []) : (r.rows || []).slice(0, 10);
  }

  return [];
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    usage();
    process.exit(0);
  }

  const sheets = await findTargetSheets(args);
  if (!sheets.length) {
    usage();
    console.log('No matching active sheets found.');
    process.exit(0);
  }

  console.log(args.apply ? 'MODE: APPLY (will update DB)' : 'MODE: DRY-RUN (no DB writes)');

  let totalUpdates = 0;
  for (const s of sheets) {
    const keys = resolveTotalQtyKeysFromColumns(s.columns);
    console.log('\n==============================');
    console.log(`Sheet ${s.id}: ${s.name}`);
    console.log(`created_at: ${s.created_at}`);
    console.log(`updated_at: ${s.updated_at}`);
    console.log(`resolved Total Quantity keys: ${keys.length ? keys.map(k => JSON.stringify(k)).join(', ') : '(none)'}`);

    if (!keys.length) continue;

    for (const key of keys) {
      const stats = await statsForKey(s.id, key);
      console.log(`\nKey ${JSON.stringify(key)}`);
      console.log(`  rows_total=${stats.rows_total} rows_with_key=${stats.rows_with_key} rows_with_nonempty=${stats.rows_with_nonempty} sum_numeric=${stats.sum_numeric}`);
      const sample = await sampleValues(s.id, key, 10);
      if (sample.length) {
        console.log('  sample values:');
        for (const r of sample) {
          console.log(`    row ${r.row_number}: ${JSON.stringify(r.value)}`);
        }
      } else {
        console.log('  sample values: (none)');
      }

      if (args.apply) {
        const updated = await removeKeyValues(s.id, key);
        totalUpdates += updated;
        console.log(`  UPDATED rows: ${updated}`);
      }
    }
  }

  if (args.apply) {
    console.log(`\nDone. Total updated sheet_data rows: ${totalUpdates}`);
  } else {
    console.log(`\nDry-run complete. Re-run with --apply to clear values.`);
  }

  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
