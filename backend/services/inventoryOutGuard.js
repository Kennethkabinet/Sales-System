const pool = require('../db');

function _isInvEncodedColumnKey(key) {
  return typeof key === 'string' && key.startsWith('INV:') && key.includes('|');
}

function _invColumnId(key) {
  if (!_isInvEncodedColumnKey(key)) return null;
  const start = 'INV:'.length;
  const sep = key.indexOf('|', start);
  if (sep <= start) return null;
  return key.substring(start, sep);
}

function _findInvColKeyById(columns, id) {
  for (const c of columns) {
    if (_invColumnId(c) === id) return c;
  }
  return null;
}

function _isInventoryTrackerColumns(columns) {
  const hasProduct =
    columns.includes('Material Name') ||
    columns.includes('Product Name') ||
    _findInvColKeyById(columns, 'product_name') !== null;
  const hasCode =
    columns.includes('QB Code') ||
    columns.includes('QC Code') ||
    _findInvColKeyById(columns, 'code') !== null;
  const hasStock = columns.includes('Stock') || _findInvColKeyById(columns, 'stock') !== null;
  const hasTotal =
    columns.includes('Total Quantity') || _findInvColKeyById(columns, 'total_qty') !== null;
  return Boolean(hasProduct && hasCode && (hasStock || hasTotal));
}

function _parseIntStrictOrNull(raw) {
  const trimmed = String(raw ?? '').trim();
  if (trimmed === '') return 0;
  if (!/^-?\d+$/.test(trimmed)) return null;
  const n = Number(trimmed);
  return Number.isSafeInteger(n) ? n : null;
}

function _parseQtyOrZero(raw) {
  const trimmed = String(raw ?? '').trim();
  if (trimmed === '') return 0;
  if (!/^-?\d+$/.test(trimmed)) return 0;
  const n = Number(trimmed);
  return Number.isSafeInteger(n) ? n : 0;
}

function _asStringMap(value) {
  if (value && typeof value === 'object' && !Array.isArray(value)) return value;
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) return parsed;
    } catch (_) {
      // ignore
    }
  }
  return {};
}

function _asStringArray(value) {
  if (Array.isArray(value)) return value.map((v) => String(v));
  if (typeof value === 'string') {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) return parsed.map((v) => String(v));
    } catch (_) {
      // ignore
    }
  }
  return [];
}

function _inventoryProductNameKey(columns) {
  return (
    _findInvColKeyById(columns, 'product_name') ||
    (columns.includes('Material Name')
      ? 'Material Name'
      : columns.includes('Product Name')
        ? 'Product Name'
        : null)
  );
}

function _inventoryCodeKey(columns) {
  return (
    _findInvColKeyById(columns, 'code') ||
    (columns.includes('QB Code') ? 'QB Code' : columns.includes('QC Code') ? 'QC Code' : null)
  );
}

function _inventoryStockKey(columns) {
  return _findInvColKeyById(columns, 'stock') || (columns.includes('Stock') ? 'Stock' : null);
}

function _inventoryTotalQtyKey(columns) {
  return (
    _findInvColKeyById(columns, 'total_qty') ||
    (columns.includes('Total Quantity') ? 'Total Quantity' : null)
  );
}

function _isInventoryRowIdentityEmpty(columns, rowData) {
  const productKey = _inventoryProductNameKey(columns);
  const codeKey = _inventoryCodeKey(columns);

  const productName = productKey ? String(rowData[productKey] ?? '').trim() : '';
  const code = codeKey ? String(rowData[codeKey] ?? '').trim() : '';

  return productName === '' && code === '';
}

function _hasAnyDateEntry(columns, rowData, { overrideOutCol, overrideOutRaw }) {
  for (const c of columns) {
    if (!c || typeof c !== 'string' || !c.startsWith('DATE:')) continue;
    const v = c === overrideOutCol ? String(overrideOutRaw ?? '').trim() : String(rowData[c] ?? '').trim();
    if (v !== '') return true;
  }
  return false;
}

function _inventoryTotalsForRow(columns, rowData, { overrideOutCol, overrideOutValue } = {}) {
  let totalIn = 0;
  let totalOut = 0;

  for (const c of columns) {
    if (!c || typeof c !== 'string') continue;
    if (c.startsWith('DATE:') && c.endsWith(':IN')) {
      totalIn += _parseQtyOrZero(rowData[c]);
    } else if (c.startsWith('DATE:') && c.endsWith(':OUT')) {
      const value = overrideOutCol && c === overrideOutCol ? overrideOutValue ?? 0 : _parseQtyOrZero(rowData[c]);
      totalOut += value;
    }
  }

  return { totalIn, totalOut, net: totalIn - totalOut };
}

function _baseStock(columns, rowData, { overrideOutCol, overrideOutRaw }) {
  const stockKey = _inventoryStockKey(columns);
  const totalKey = _inventoryTotalQtyKey(columns);

  const stockRaw = stockKey ? String(rowData[stockKey] ?? '').trim() : '';
  const totalRaw = totalKey ? String(rowData[totalKey] ?? '').trim() : '';

  // If Stock is blank but Total Quantity exists, treat Total Quantity as the baseline.
  const baseRaw = stockRaw !== '' ? stockRaw : totalRaw;

  return _parseQtyOrZero(baseRaw);
}

async function inventoryOutEditWouldBeInvalid({
  sheetId,
  rowNumber,
  columnName,
  proposedValue,
}) {
  // Only applies to Inventory Tracker OUT date columns.
  if (typeof columnName !== 'string' || !columnName.startsWith('DATE:') || !columnName.endsWith(':OUT')) {
    return { invalid: false, reason: null };
  }

  const sid = Number(sheetId);
  const rn = Number(rowNumber);
  if (!Number.isFinite(sid) || sid <= 0 || !Number.isFinite(rn) || rn <= 0) {
    return { invalid: false, reason: null };
  }

  const sheetRes = await pool.query('SELECT columns FROM sheets WHERE id = $1', [sid]);
  if (sheetRes.rows.length === 0) {
    return { invalid: false, reason: null };
  }

  const columns = _asStringArray(sheetRes.rows[0].columns);
  if (!_isInventoryTrackerColumns(columns)) {
    return { invalid: false, reason: null };
  }

  const rowRes = await pool.query(
    'SELECT data FROM sheet_data WHERE sheet_id = $1 AND row_number = $2',
    [sid, rn]
  );
  const rowData = _asStringMap(rowRes.rows[0]?.data);

  if (_isInventoryRowIdentityEmpty(columns, rowData)) {
    return { invalid: false, reason: null };
  }

  const proposedTrimmed = String(proposedValue ?? '').trim();
  const proposedOut = _parseIntStrictOrNull(proposedTrimmed);
  if (proposedOut === null || proposedOut < 0) {
    return { invalid: true, reason: 'Invalid amount. OUT must be a non-negative integer.' };
  }

  const totalsBefore = _inventoryTotalsForRow(columns, rowData);
  const totalsAfter = _inventoryTotalsForRow(columns, rowData, {
    overrideOutCol: columnName,
    overrideOutValue: proposedOut,
  });

  const currentOut = _parseQtyOrZero(rowData[columnName]);

  const beforeTotal =
    _baseStock(columns, rowData, { overrideOutCol: null, overrideOutRaw: null }) +
    (totalsBefore.net ?? 0);
  const afterTotal =
    _baseStock(columns, rowData, { overrideOutCol: columnName, overrideOutRaw: proposedTrimmed }) +
    (totalsAfter.net ?? 0);

  if (afterTotal >= 0) {
    return { invalid: false, reason: null };
  }

  // Allow fixing an already-invalid row by reducing OUT.
  const isReducingOut = proposedOut <= currentOut;
  if (beforeTotal < 0 && isReducingOut && afterTotal >= beforeTotal) {
    return { invalid: false, reason: null };
  }

  return {
    invalid: true,
    reason: 'Invalid amount. Total quantity cannot be negative.',
  };
}

async function inventoryInEditWouldBeInvalid({
  sheetId,
  rowNumber,
  columnName,
  proposedValue,
}) {
  // Only applies to Inventory Tracker IN date columns.
  if (typeof columnName !== 'string' || !columnName.startsWith('DATE:') || !columnName.endsWith(':IN')) {
    return { invalid: false, reason: null };
  }

  const sid = Number(sheetId);
  const rn = Number(rowNumber);
  if (!Number.isFinite(sid) || sid <= 0 || !Number.isFinite(rn) || rn <= 0) {
    return { invalid: false, reason: null };
  }

  const sheetRes = await pool.query('SELECT columns FROM sheets WHERE id = $1', [sid]);
  if (sheetRes.rows.length === 0) {
    return { invalid: false, reason: null };
  }

  const columns = _asStringArray(sheetRes.rows[0].columns);
  if (!_isInventoryTrackerColumns(columns)) {
    return { invalid: false, reason: null };
  }

  const rowRes = await pool.query(
    'SELECT data FROM sheet_data WHERE sheet_id = $1 AND row_number = $2',
    [sid, rn]
  );
  const rowData = _asStringMap(rowRes.rows[0]?.data);

  if (_isInventoryRowIdentityEmpty(columns, rowData)) {
    return { invalid: false, reason: null };
  }

  const proposedTrimmed = String(proposedValue ?? '').trim();
  const proposedIn = _parseIntStrictOrNull(proposedTrimmed);
  if (proposedIn === null || proposedIn < 0) {
    return { invalid: true, reason: 'Invalid amount. IN must be a non-negative integer.' };
  }

  return { invalid: false, reason: null };
}

async function inventoryDateQtyEditWouldBeInvalid(args) {
  const columnName = args?.columnName;
  if (typeof columnName !== 'string' || !columnName.startsWith('DATE:')) {
    return { invalid: false, reason: null };
  }
  if (columnName.endsWith(':OUT')) {
    return inventoryOutEditWouldBeInvalid(args);
  }
  if (columnName.endsWith(':IN')) {
    return inventoryInEditWouldBeInvalid(args);
  }
  return { invalid: false, reason: null };
}

module.exports = {
  inventoryOutEditWouldBeInvalid,
  inventoryInEditWouldBeInvalid,
  inventoryDateQtyEditWouldBeInvalid,
};
