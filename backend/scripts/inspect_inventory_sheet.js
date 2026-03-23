/*
  Inspect Inventory Tracker sheet values in Postgres.

  Usage:
    node scripts/inspect_inventory_sheet.js --sheet-name "March Inventory"
    node scripts/inspect_inventory_sheet.js --sheet-id 123

  Prints:
    - matching sheet(s)
    - presence of Stock / Total Quantity keys (legacy + encoded)
    - sum of numeric values found in sheet_data for those keys
*/

require('dotenv').config();
const pool = require('../db');

function parseArgs(argv) {
  const out = { sheetId: null, sheetName: null, nameLike: null, all: false, listInventory: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--sheet-id') out.sheetId = parseInt(argv[++i] || '', 10);
    else if (a === '--sheet-name') out.sheetName = argv[++i] || '';
    else if (a === '--name-like') out.nameLike = argv[++i] || '';
    else if (a === '--all') out.all = true;
    else if (a === '--list-inventory') out.listInventory = true;
    else if (a === '--help' || a === '-h') out.help = true;
  }
  return out;
}

function usage() {
  console.log(`\nInspect Inventory sheet\n\n` +
    `Usage:\n` +
    `  node scripts/inspect_inventory_sheet.js --sheet-id <id>\n` +
    `  node scripts/inspect_inventory_sheet.js --sheet-name <name> [--all]\n` +
    `  node scripts/inspect_inventory_sheet.js --name-like <pattern> [--all]\n` +
    `  node scripts/inspect_inventory_sheet.js --list-inventory\n`);
}

function firstKey(columns, predicate) {
  for (const c of columns) {
    if (predicate(c)) return c;
  }
  return null;
}

function isEncodedKey(col, id) {
  return typeof col === 'string' && col.startsWith(`INV:${id}|`);
}

async function sumForKey(sheetId, key) {
  // Coerce (data->>key) into numeric when possible; ignore empty.
  const sql = `
    SELECT
      COUNT(*)::int AS row_count,
      SUM((NULLIF(REPLACE((data->>$2), ',', ''), '')::numeric)) AS sum
    FROM sheet_data
    WHERE sheet_id = $1
  `;
  const r = await pool.query(sql, [sheetId, key]);
  return r.rows?.[0] ?? { row_count: 0, sum: null };
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    usage();
    process.exit(0);
  }

  let sheets = [];
  if (Number.isInteger(args.sheetId) && args.sheetId > 0) {
    const r = await pool.query(
      `SELECT id, name, created_at, updated_at, columns FROM sheets WHERE id=$1 AND is_active=TRUE`,
      [args.sheetId]
    );
    sheets = r.rows || [];
  } else {
    if (args.listInventory) {
      const r = await pool.query(
        `SELECT id, name, created_at, updated_at, columns
         FROM sheets
         WHERE is_active=TRUE
         ORDER BY id DESC
         LIMIT 50`
      );
      const rows = r.rows || [];
      sheets = rows.filter((s) => {
        const cols = Array.isArray(s.columns) ? s.columns : [];
        return cols.some((c) => c === 'Stock' || c === 'Total Quantity' ||
          (typeof c === 'string' && (c.startsWith('INV:stock|') || c.startsWith('INV:total_qty|'))));
      });
    } else if ((args.sheetName || '').trim()) {
      const name = (args.sheetName || '').trim();
      const r = await pool.query(
        `SELECT id, name, created_at, updated_at, columns FROM sheets WHERE name=$1 AND is_active=TRUE ORDER BY id DESC`,
        [name]
      );
      sheets = args.all ? (r.rows || []) : (r.rows || []).slice(0, 1);
    } else if ((args.nameLike || '').trim()) {
      const pattern = (args.nameLike || '').trim();
      const r = await pool.query(
        `SELECT id, name, created_at, updated_at, columns
         FROM sheets
         WHERE is_active=TRUE AND name ILIKE $1
         ORDER BY id DESC`,
        [pattern]
      );
      sheets = args.all ? (r.rows || []) : (r.rows || []).slice(0, 10);
    } else {
      usage();
      console.error('Error: Provide --sheet-id, --sheet-name, --name-like, or --list-inventory.');
      process.exit(1);
    }
  }

  if (!sheets.length) {
    console.log('No matching active sheets found.');
    process.exit(0);
  }

  for (const s of sheets) {
    const columns = Array.isArray(s.columns) ? s.columns : [];
    const stockKey = firstKey(columns, (c) => c === 'Stock' || isEncodedKey(c, 'stock'));
    const totalKey = firstKey(columns, (c) => c === 'Total Quantity' || isEncodedKey(c, 'total_qty'));

    console.log('\n==============================');
    console.log(`Sheet ${s.id}: ${s.name}`);
    console.log(`created_at: ${s.created_at}`);
    console.log(`updated_at: ${s.updated_at}`);
    console.log(`columns: ${columns.length}`);
    console.log(`stockKey: ${stockKey}`);
    console.log(`totalKey: ${totalKey}`);

    const keys = [
      { label: 'Stock', key: 'Stock' },
      { label: 'Stock(encoded)', key: stockKey && stockKey !== 'Stock' ? stockKey : null },
      { label: 'Total Quantity', key: 'Total Quantity' },
      { label: 'Total Quantity(encoded)', key: totalKey && totalKey !== 'Total Quantity' ? totalKey : null },
    ].filter(x => x.key);

    for (const { label, key } of keys) {
      const stats = await sumForKey(s.id, key);
      console.log(`${label} key=${JSON.stringify(key)} rows=${stats.row_count} sum=${stats.sum}`);
    }
  }

  await pool.end();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
