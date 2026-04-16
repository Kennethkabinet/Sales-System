const express = require('express');
const router = express.Router();
const pool = require('../db');

const { inventoryDateQtyEditWouldBeInvalid } = require('../services/inventoryOutGuard');
const multer = require('multer');
const { authenticate } = require('../middleware/auth');
const { 
  requireSheetAccess, 
  requireSheetEditAccess,
  requireRole 
} = require('../middleware/rbac');
const auditService = require('../services/auditService');
const ExcelJS = require('exceljs');
const bcrypt = require('bcrypt');
const path = require('path');

const toCsv = (rows) => {
  const escapeCell = (v) => {
    if (v === null || v === undefined) return '';
    const s = String(v);
    if (/[\r\n",]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
    return s;
  };
  return rows.map((r) => (r || []).map(escapeCell).join(',')).join('\r\n') + '\r\n';
};

const parseCsv = (text) => {
  const rows = [];
  let row = [];
  let cur = '';
  let inQuotes = false;

  for (let i = 0; i < text.length; i++) {
    const ch = text[i];
    const next = i + 1 < text.length ? text[i + 1] : '';

    if (inQuotes) {
      if (ch === '"' && next === '"') {
        cur += '"';
        i++;
      } else if (ch === '"') {
        inQuotes = false;
      } else {
        cur += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
      continue;
    }
    if (ch === ',') {
      row.push(cur);
      cur = '';
      continue;
    }
    if (ch === '\r') {
      if (next === '\n') i++;
      row.push(cur);
      rows.push(row);
      row = [];
      cur = '';
      continue;
    }
    if (ch === '\n') {
      row.push(cur);
      rows.push(row);
      row = [];
      cur = '';
      continue;
    }
    cur += ch;
  }

  row.push(cur);
  rows.push(row);
  return rows.filter((r) => r.some((c) => String(c ?? '').trim() !== ''));
};

const worksheetToAoa = (worksheet, { defval = '' } = {}) => {
  if (!worksheet) return [];
  const maxCols = Math.max(
    worksheet.columnCount || 0,
    worksheet.getRow(1)?.cellCount || 0
  );
  const rows = [];
  worksheet.eachRow({ includeEmpty: true }, (row, rowNumber) => {
    const rowArr = [];
    for (let c = 1; c <= maxCols; c++) {
      const cell = row.getCell(c);
      const value = cell?.value;

      if (value === null || value === undefined) {
        rowArr.push(defval);
        continue;
      }
      if (typeof value === 'object') {
        if (value.richText) {
          rowArr.push(value.richText.map((t) => t.text).join(''));
        } else if (value.formula !== undefined) {
          rowArr.push(value.result ?? defval);
        } else if (value.text !== undefined) {
          rowArr.push(value.text);
        } else {
          rowArr.push(cell.text ?? String(value));
        }
      } else {
        rowArr.push(value);
      }
    }
    rows[rowNumber - 1] = rowArr;
  });
  return rows;
};

// Multer memory storage for sheet file imports
const uploadMemory = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024 } });

// Self-healing migration: add password_hash columns for folder/sheet password protection
pool.query(`
  ALTER TABLE sheets ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
  ALTER TABLE folders ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
`).catch(err => console.error('[Migration] password_hash columns:', err.message));

// Self-healing migration: grid metadata (cell formatting, merged cells, borders, etc.)
pool.query(`
  ALTER TABLE sheets ADD COLUMN IF NOT EXISTS grid_meta JSONB DEFAULT '{}'::jsonb;
`).catch(err => console.error('[Migration] grid_meta column:', err.message));

// Self-healing migration: active users heartbeat table for per-sheet presence polling
pool.query(`
  CREATE TABLE IF NOT EXISTS active_users (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    sheet_id INTEGER NOT NULL REFERENCES sheets(id) ON DELETE CASCADE,
    last_active_timestamp TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, sheet_id)
  );

  CREATE INDEX IF NOT EXISTS idx_active_users_sheet_last_active
  ON active_users (sheet_id, last_active_timestamp DESC);
`).catch(err => console.error('[Migration] active_users table:', err.message));

// GET /sheets - Get all sheets for user
router.get('/', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const offset = (page - 1) * limit;

    let query;
    let countQuery;
    let params;
    let countParams;

    const folderIdParam = req.query.folder_id;
    let folderCondition = '';
    let folderConditionCount = '';
    if (folderIdParam !== undefined) {
      if (folderIdParam === 'root' || folderIdParam === '') {
        folderCondition = 'AND s.folder_id IS NULL';
        folderConditionCount = 'AND folder_id IS NULL';
      } else {
        const fid = parseInt(folderIdParam);
        if (!isNaN(fid)) {
          folderCondition = `AND s.folder_id = ${fid}`;
          folderConditionCount = `AND folder_id = ${fid}`;
        }
      }
    }

    if (req.user.role === 'admin') {
      // Admin sees all sheets
      query = `
        SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
               s.created_at, s.updated_at, s.last_edited_by, le.username as last_edited_by_name,
               s.shown_to_viewers, s.folder_id, f.name as folder_name,
               sl.locked_by, lu.username as locked_by_name, sl.locked_at,
               ses.user_id as editing_user_id, seu.username as editing_user_name
        FROM sheets s
        LEFT JOIN users u ON s.created_by = u.id
        LEFT JOIN users le ON s.last_edited_by = le.id
        LEFT JOIN folders f ON s.folder_id = f.id
        LEFT JOIN sheet_locks sl ON s.id = sl.sheet_id AND sl.expires_at > CURRENT_TIMESTAMP
        LEFT JOIN users lu ON sl.locked_by = lu.id
        LEFT JOIN sheet_edit_sessions ses ON s.id = ses.sheet_id AND ses.is_active = TRUE AND ses.last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
        LEFT JOIN users seu ON ses.user_id = seu.id
        WHERE s.is_active = TRUE ${folderCondition}
        ORDER BY s.updated_at DESC
        LIMIT $1 OFFSET $2
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE ${folderConditionCount}`;
      params = [limit, offset];
      countParams = [];
    } else if (req.user.role === 'viewer') {
      // Viewers only see sheets shown to them by admin
      query = `
        SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
               s.created_at, s.updated_at, s.last_edited_by, le.username as last_edited_by_name,
               s.shown_to_viewers, s.folder_id, f.name as folder_name,
               sl.locked_by, lu.username as locked_by_name, sl.locked_at,
               ses.user_id as editing_user_id, seu.username as editing_user_name
        FROM sheets s
        LEFT JOIN users u ON s.created_by = u.id
        LEFT JOIN users le ON s.last_edited_by = le.id
        LEFT JOIN folders f ON s.folder_id = f.id
        LEFT JOIN sheet_locks sl ON s.id = sl.sheet_id AND sl.expires_at > CURRENT_TIMESTAMP
        LEFT JOIN users lu ON sl.locked_by = lu.id
        LEFT JOIN sheet_edit_sessions ses ON s.id = ses.sheet_id AND ses.is_active = TRUE AND ses.last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
        LEFT JOIN users seu ON ses.user_id = seu.id
        WHERE s.is_active = TRUE AND s.shown_to_viewers = TRUE ${folderCondition}
        ORDER BY s.updated_at DESC
        LIMIT $1 OFFSET $2
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE AND shown_to_viewers = TRUE ${folderConditionCount}`;
      params = [limit, offset];
      countParams = [];
    } else if (req.user.role === 'editor') {
      // Editors see all sheets (they need access to edit any sheet)
      query = `
        SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
               s.created_at, s.updated_at, s.last_edited_by, le.username as last_edited_by_name,
               s.shown_to_viewers, s.folder_id, f.name as folder_name,
               sl.locked_by, lu.username as locked_by_name, sl.locked_at,
               ses.user_id as editing_user_id, seu.username as editing_user_name
        FROM sheets s
        LEFT JOIN users u ON s.created_by = u.id
        LEFT JOIN users le ON s.last_edited_by = le.id
        LEFT JOIN folders f ON s.folder_id = f.id
        LEFT JOIN sheet_locks sl ON s.id = sl.sheet_id AND sl.expires_at > CURRENT_TIMESTAMP
        LEFT JOIN users lu ON sl.locked_by = lu.id
        LEFT JOIN sheet_edit_sessions ses ON s.id = ses.sheet_id AND ses.is_active = TRUE AND ses.last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
        LEFT JOIN users seu ON ses.user_id = seu.id
        WHERE s.is_active = TRUE ${folderCondition}
        ORDER BY s.updated_at DESC
        LIMIT $1 OFFSET $2
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE ${folderConditionCount}`;
      params = [limit, offset];
      countParams = [];
    } else {
      // Regular users see their own sheets or shared sheets
      query = `
        SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
               s.created_at, s.updated_at, s.last_edited_by, le.username as last_edited_by_name,
               s.shown_to_viewers, s.folder_id, f.name as folder_name,
               sl.locked_by, lu.username as locked_by_name, sl.locked_at,
               ses.user_id as editing_user_id, seu.username as editing_user_name
        FROM sheets s
        LEFT JOIN users u ON s.created_by = u.id
        LEFT JOIN users le ON s.last_edited_by = le.id
        LEFT JOIN folders f ON s.folder_id = f.id
        LEFT JOIN sheet_locks sl ON s.id = sl.sheet_id AND sl.expires_at > CURRENT_TIMESTAMP
        LEFT JOIN users lu ON sl.locked_by = lu.id
        LEFT JOIN sheet_edit_sessions ses ON s.id = ses.sheet_id AND ses.is_active = TRUE AND ses.last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
        LEFT JOIN users seu ON ses.user_id = seu.id
        WHERE s.is_active = TRUE AND (s.created_by = $1 OR s.is_shared = TRUE) ${folderCondition}
        ORDER BY s.updated_at DESC
        LIMIT $2 OFFSET $3
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE AND (created_by = $1 OR is_shared = TRUE) ${folderConditionCount}`;
      params = [req.user.id, limit, offset];
      countParams = [req.user.id];
    }

    const [sheetsResult, countResult] = await Promise.all([
      pool.query(query, params),
      pool.query(countQuery, countParams)
    ]);

    const total = parseInt(countResult.rows[0]?.total || 0);

    // Fetch folders for the current level
    let folderQuery;
    let folderQueryParams = [];
    let fpIdx = 1;
    const isAdmin = req.user.role === 'admin';
    const isViewer = req.user.role === 'viewer';
    const parentCondition = (folderIdParam !== undefined && folderIdParam !== 'root' && folderIdParam !== '')
      ? `fo.parent_id = $${fpIdx++}` : 'fo.parent_id IS NULL';
    if (isAdmin) {
      // Admins see all folders
      folderQuery = `SELECT fo.id, fo.name, fo.parent_id, u.username as created_by, fo.created_at, fo.updated_at,
              (SELECT COUNT(*) FROM sheets s2 WHERE s2.folder_id = fo.id AND s2.is_active = TRUE) as sheet_count
       FROM folders fo LEFT JOIN users u ON fo.created_by = u.id
       WHERE fo.is_active = TRUE AND ${parentCondition}
       ORDER BY fo.name ASC`;
      if (folderIdParam !== undefined && folderIdParam !== 'root' && folderIdParam !== '') {
        folderQueryParams.push(parseInt(folderIdParam));
      }
    } else if (isViewer) {
      // Viewers see only folders that contain (directly or via nested sub-folders) at
      // least one sheet with shown_to_viewers = TRUE. A recursive CTE walks UP the
      // folder tree from the leaf folders that own visible sheets so that all ancestor
      // folders are also surfaced for navigation purposes.
      folderQuery = `
        WITH RECURSIVE visible_folder_ids AS (
          -- Base: folders that directly contain at least one viewer-visible sheet
          SELECT DISTINCT s.folder_id AS id
          FROM sheets s
          WHERE s.is_active = TRUE AND s.shown_to_viewers = TRUE AND s.folder_id IS NOT NULL
          UNION
          -- Recursive: parent folders of already-identified visible folders
          SELECT fo.parent_id
          FROM folders fo
          INNER JOIN visible_folder_ids vf ON fo.id = vf.id
          WHERE fo.parent_id IS NOT NULL AND fo.is_active = TRUE
        )
        SELECT fo.id, fo.name, fo.parent_id, u.username as created_by, fo.created_at, fo.updated_at,
               (SELECT COUNT(*) FROM sheets s2
                WHERE s2.folder_id = fo.id AND s2.is_active = TRUE AND s2.shown_to_viewers = TRUE) as sheet_count
        FROM folders fo
        LEFT JOIN users u ON fo.created_by = u.id
        WHERE fo.is_active = TRUE
          AND fo.id IN (SELECT id FROM visible_folder_ids)
          AND ${parentCondition}
        ORDER BY fo.name ASC`;
      if (folderIdParam !== undefined && folderIdParam !== 'root' && folderIdParam !== '') {
        folderQueryParams.push(parseInt(folderIdParam));
      }
    } else {
      // Editors and regular users see all active folders (not just their own)
      folderQuery = `SELECT fo.id, fo.name, fo.parent_id, u.username as created_by, fo.created_at, fo.updated_at,
              (SELECT COUNT(*) FROM sheets s2 WHERE s2.folder_id = fo.id AND s2.is_active = TRUE) as sheet_count
       FROM folders fo LEFT JOIN users u ON fo.created_by = u.id
       WHERE fo.is_active = TRUE AND ${parentCondition}
       ORDER BY fo.name ASC`;
      if (folderIdParam !== undefined && folderIdParam !== 'root' && folderIdParam !== '') {
        folderQueryParams.push(parseInt(folderIdParam));
      }
    }
    const foldersResult = await pool.query(folderQuery, folderQueryParams);

    // Augment rows with has_password — never send the actual hash to the client
    const sheetIds = sheetsResult.rows.map(r => r.id);
    if (sheetIds.length > 0) {
      const pwResult = await pool.query(
        `SELECT id, (password_hash IS NOT NULL) as has_password FROM sheets WHERE id = ANY($1)`,
        [sheetIds]
      );
      const pwMap = {};
      pwResult.rows.forEach(r => { pwMap[r.id] = r.has_password; });
      sheetsResult.rows.forEach(r => { r.has_password = pwMap[r.id] || false; });
    }
    const folderIds = foldersResult.rows.map(f => f.id);
    if (folderIds.length > 0) {
      const fpwResult = await pool.query(
        `SELECT id, (password_hash IS NOT NULL) as has_password FROM folders WHERE id = ANY($1)`,
        [folderIds]
      );
      const fpwMap = {};
      fpwResult.rows.forEach(r => { fpwMap[r.id] = r.has_password; });
      foldersResult.rows.forEach(r => { r.has_password = fpwMap[r.id] || false; });
    }

    res.json({
      success: true,
      sheets: sheetsResult.rows,
      folders: foldersResult.rows,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit)
      }
    });
  } catch (error) {
    console.error('Get sheets error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get sheets' }
    });
  }
});

// POST /sheets/import-file - Create a new sheet from an uploaded Excel/CSV file
router.post('/import-file', authenticate, requireSheetEditAccess, uploadMemory.single('file'), async (req, res) => {
  try {
    if (!['admin', 'manager', 'editor'].includes(req.user.role)) {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Insufficient permissions' } });
    }
    if (!req.file) {
      return res.status(400).json({ success: false, error: { code: 'NO_FILE', message: 'No file uploaded' } });
    }

    const originalName = req.file.originalname || 'Imported Sheet';
    const sheetName = req.body.name || originalName.replace(/\.(xlsx?|csv)$/i, '');

    const ext = path.extname(originalName).toLowerCase();
    let rawData;
    if (ext === '.csv') {
      const text = req.file.buffer.toString('utf8');
      rawData = parseCsv(text);
    } else if (ext === '.xlsx') {
      const wb = new ExcelJS.Workbook();
      await wb.xlsx.load(req.file.buffer);
      const ws = wb.worksheets[0];
      rawData = worksheetToAoa(ws, { defval: '' });
    } else if (ext === '.xls') {
      return res.status(400).json({
        success: false,
        error: { code: 'UNSUPPORTED_FORMAT', message: 'Legacy .xls is not supported. Please save as .xlsx or .csv.' }
      });
    } else {
      return res.status(400).json({
        success: false,
        error: { code: 'UNSUPPORTED_FORMAT', message: 'Unsupported file type. Please upload a .xlsx or .csv file.' }
      });
    }

    if (!rawData || rawData.length === 0) {
      return res.status(400).json({ success: false, error: { code: 'EMPTY_FILE', message: 'The file appears to be empty' } });
    }

    const toCellStr = (v) => (v == null ? '' : String(v)).trim();

    const parseMaintainingLegacy = (raw) => {
      const t = toCellStr(raw);
      if (!t) return { qty: '', unit: '' };
      const lower = t.toLowerCase();
      if (lower === 'pr' || lower === 'per request' || lower === 'per-request') {
        return { qty: '-', unit: 'PR' };
      }
      const cleaned = t.replace(/,/g, '');
      const m = cleaned.match(/^(-?\d+(?:\.\d+)?)(?:\s+(.+))?$/);
      if (!m) return { qty: '', unit: '' };
      return { qty: toCellStr(m[1]), unit: toCellStr(m[2] || '') };
    };


    const header1 = (rawData[0] || []).map(toCellStr);
    const header2 = (rawData[1] || []).map(toCellStr);

    const looksLikeInventoryExport = (() => {
      if (rawData.length < 2) return false;
      const hasProduct = header1.includes('Material Name') || header1.includes('Product Name');
      const hasCode = header1.includes('QC Code') || header1.includes('QB Code');
      const hasMaintaining =
        header1.includes('Maintaining') ||
        header1.includes('Maintaining Qty') ||
        header1.includes('Maintaining Unit') ||
        header1.includes('Maintaining Status');
      const hasTotal = header1.includes('Total Quantity');
      if (!hasProduct || !hasCode || !hasMaintaining || !hasTotal) return false;

      const maintainingEndIdx = Math.max(
        header1.indexOf('Maintaining Unit'),
        header1.indexOf('Maintaining Qty'),
        header1.indexOf('Maintaining')
      );
      const criticalIdx = header1.indexOf('Critical');
      const totalIdx = header1.indexOf('Total Quantity');
      const leftEndIdx = criticalIdx >= 0 ? criticalIdx : maintainingEndIdx;
      if (leftEndIdx < 0 || totalIdx < 0 || totalIdx <= leftEndIdx + 1) return false;

      for (let i = leftEndIdx + 1; i + 1 < totalIdx; i += 2) {
        const inVal = (header2[i] || '').toUpperCase();
        const outVal = (header2[i + 1] || '').toUpperCase();
        const label = header1[i];
        if (label && inVal === 'IN' && outVal === 'OUT') return true;
      }
      return false;
    })();

    const monthMap = {
      jan: 1,
      feb: 2,
      mar: 3,
      apr: 4,
      may: 5,
      jun: 6,
      jul: 7,
      aug: 8,
      sep: 9,
      oct: 10,
      nov: 11,
      dec: 12,
    };

    const tryParseInventoryHeaderDateToIso = (label) => {
      const raw = toCellStr(label).replace(/\s+TODAY\s*/i, ' ').trim();
      if (!raw) return null;
      if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) return raw;

      const parts = raw
        .replace(/[,]/g, ' ')
        .split(/\s+|\-|\//)
        .map((p) => p.trim())
        .filter(Boolean);
      if (parts.length < 2) return null;

      const monKey = parts[0].slice(0, 3).toLowerCase();
      const month = monthMap[monKey];
      const day = parseInt(parts[1], 10);
      if (!month || !Number.isFinite(day)) return null;

      const now = new Date();
      let year = now.getFullYear();
      if (parts.length >= 3) {
        const maybeYear = parseInt(parts[2], 10);
        if (Number.isFinite(maybeYear) && maybeYear >= 1970 && maybeYear <= 2100) {
          year = maybeYear;
        }
      }

      // If year was not explicitly present, apply a simple year-boundary heuristic.
      if (parts.length < 3) {
        const candidate = new Date(year, month - 1, day);
        const diffDays = (candidate.getTime() - now.getTime()) / (1000 * 60 * 60 * 24);
        if (diffDays > 90) year -= 1; // e.g. importing "Dec 31" in early Jan
        if (diffDays < -275) year += 1; // e.g. importing "Jan 2" in late Dec
      }

      const dt = new Date(year, month - 1, day);
      const yyyy = String(dt.getFullYear()).padStart(4, '0');
      const mm = String(dt.getMonth() + 1).padStart(2, '0');
      const dd = String(dt.getDate()).padStart(2, '0');
      return `${yyyy}-${mm}-${dd}`;
    };

    let columns;
    let dataRows;

    if (looksLikeInventoryExport) {
      const productColInFile = header1.includes('Material Name') ? 'Material Name' : 'Product Name';
      const codeColInFile = header1.includes('QB Code') ? 'QB Code' : 'QC Code';
      const productIdx = header1.indexOf(productColInFile);
      const codeIdx = header1.indexOf(codeColInFile);
      const stockIdx = header1.indexOf('Stock');
      const maintainingLegacyIdx = header1.indexOf('Maintaining');
      const maintainingQtyIdx = header1.indexOf('Maintaining Qty');
      const maintainingUnitIdx = header1.indexOf('Maintaining Unit');
      const maintainingStatusIdx = header1.indexOf('Maintaining Status');
      const criticalIdx = header1.indexOf('Critical');
      const totalIdx = header1.indexOf('Total Quantity');
      const maintainingEndIdx = Math.max(
        maintainingUnitIdx,
        maintainingQtyIdx,
        maintainingLegacyIdx,
      );
      const leftEndIdx = criticalIdx >= 0 ? criticalIdx : maintainingEndIdx;

      // Collect date pairs from header row 1 + IN/OUT from header row 2.
      const datePairs = [];
      for (let i = leftEndIdx + 1; i + 1 < totalIdx; i += 2) {
        const label = header1[i];
        const inVal = (header2[i] || '').toUpperCase();
        const outVal = (header2[i + 1] || '').toUpperCase();
        if (!label || inVal !== 'IN' || outVal !== 'OUT') continue;

        const iso = tryParseInventoryHeaderDateToIso(label);
        if (!iso) continue;
        datePairs.push({
          iso,
          inIdx: i,
          outIdx: i + 1,
        });
      }

      // Build internal Inventory Tracker column schema.
      columns = ['Material Name', 'QB Code', 'Stock', 'Maintaining Qty', 'Maintaining Unit', 'Critical'];
      for (const p of datePairs) {
        columns.push(`DATE:${p.iso}:IN`, `DATE:${p.iso}:OUT`);
      }
      columns.push('Total Quantity');

      // Skip the 2nd header row from data.
      const startRowIdx = 2;
      dataRows = rawData.slice(startRowIdx).map((rowArr) => {
        const row = Array.isArray(rowArr) ? rowArr : [];
        const rowObj = {};
        const totalVal = row[totalIdx] !== undefined ? String(row[totalIdx]) : '';

        let mQty = '';
        let mUnit = '';

        const hasSplitMaintaining = maintainingQtyIdx >= 0 || maintainingUnitIdx >= 0 || maintainingStatusIdx >= 0;
        if (hasSplitMaintaining) {
          if (maintainingQtyIdx >= 0 && row[maintainingQtyIdx] !== undefined) mQty = String(row[maintainingQtyIdx]);
          if (maintainingUnitIdx >= 0 && row[maintainingUnitIdx] !== undefined) mUnit = String(row[maintainingUnitIdx]);

          const statusNorm = toCellStr(maintainingStatusIdx >= 0 && row[maintainingStatusIdx] !== undefined ? String(row[maintainingStatusIdx]) : '').toLowerCase();
          mQty = toCellStr(mQty);
          mUnit = toCellStr(mUnit);

          const isPr =
            statusNorm === 'pr' || statusNorm === 'per request' || statusNorm === 'per-request' ||
            toCellStr(mUnit).toLowerCase() === 'pr' ||
            toCellStr(mQty) === '-';
          if (isPr) {
            mQty = '-';
            mUnit = 'PR';
          }
        } else {
          const legacyVal = maintainingLegacyIdx >= 0 && row[maintainingLegacyIdx] !== undefined ? String(row[maintainingLegacyIdx]) : '';
          const parsed = parseMaintainingLegacy(legacyVal);
          mQty = parsed.qty;
          mUnit = parsed.unit;
        }

        rowObj['Material Name'] = (productIdx >= 0 && row[productIdx] !== undefined)
            ? String(row[productIdx])
            : '';
        rowObj['QB Code'] = (codeIdx >= 0 && row[codeIdx] !== undefined)
            ? String(row[codeIdx])
            : '';
        rowObj['Maintaining Qty'] = mQty;
        rowObj['Maintaining Unit'] = mUnit;

        // Stock/Critical may be missing in older exports; derive defaults.
        if (stockIdx >= 0 && row[stockIdx] !== undefined) {
          rowObj['Stock'] = String(row[stockIdx]);
        } else {
          const t = String(totalVal ?? '').trim();
          rowObj['Stock'] = t.length ? t : '0';
        }
        if (criticalIdx >= 0 && row[criticalIdx] !== undefined) {
          rowObj['Critical'] = String(row[criticalIdx]);
        } else {
          const unitUp = toCellStr(mUnit).toUpperCase();
          const qtyNum = parseFloat(String(mQty || '').replace(/,/g, ''));
          if (unitUp === 'PR' || toCellStr(mQty) === '-' || !Number.isFinite(qtyNum) || qtyNum <= 0) {
            rowObj['Critical'] = '0';
          } else {
            rowObj['Critical'] = String(Math.round(qtyNum));
          }
        }

        for (const p of datePairs) {
          rowObj[`DATE:${p.iso}:IN`] = row[p.inIdx] !== undefined ? String(row[p.inIdx]) : '';
          rowObj[`DATE:${p.iso}:OUT`] = row[p.outIdx] !== undefined ? String(row[p.outIdx]) : '';
        }
        rowObj['Total Quantity'] = totalVal;
        return rowObj;
      });
    } else {
      // First row = column headers
      columns = (rawData[0] || []).map((c, i) => (c ? String(c) : `Column${i + 1}`));
      dataRows = rawData.slice(1).map((rowArr) => {
        const row = Array.isArray(rowArr) ? rowArr : [];
        const rowObj = {};
        columns.forEach((col, idx) => {
          rowObj[col] = row[idx] !== undefined ? String(row[idx]) : '';
        });
        return rowObj;
      });
    }

    // Create the sheet record
    const sheetResult = await pool.query(`
      INSERT INTO sheets (name, columns, created_by, last_edited_by)
      VALUES ($1, $2, $3, $3)
      RETURNING id, name, columns, created_by, created_at, updated_at
    `, [sheetName, JSON.stringify(columns), req.user.id]);

    const sheet = sheetResult.rows[0];

    // Insert rows
    for (let i = 0; i < dataRows.length; i++) {
      await pool.query(
        'INSERT INTO sheet_data (sheet_id, row_number, data) VALUES ($1, $2, $3)',
        [sheet.id, i + 1, JSON.stringify(dataRows[i])]
      );
    }

    await auditService.log({
      userId: req.user.id,
      action: 'IMPORT',
      entityType: 'sheets',
      entityId: sheet.id,
      metadata: { rowCount: dataRows.length, columnCount: columns.length, source: originalName }
    });

    res.json({
      success: true,
      sheet: { ...sheet, rows: dataRows },
      rowCount: dataRows.length,
      columnCount: columns.length
    });
  } catch (error) {
    console.error('Import sheet file error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to import file: ' + error.message } });
  }
});

// GET /sheets/folders - List all folders (for move-to-folder picker)
router.get('/folders', authenticate, async (req, res) => {
  try {
    const isAdmin = req.user.role === 'admin';
    let foldersResult;
    if (isAdmin) {
      foldersResult = await pool.query(`
        SELECT fo.id, fo.name, fo.parent_id, u.username as created_by, fo.created_at,
               (SELECT COUNT(*) FROM sheets s WHERE s.folder_id = fo.id AND s.is_active = TRUE) as sheet_count
        FROM folders fo
        LEFT JOIN users u ON fo.created_by = u.id
        WHERE fo.is_active = TRUE
        ORDER BY fo.name ASC
      `);
    } else {
      foldersResult = await pool.query(`
        SELECT fo.id, fo.name, fo.parent_id, u.username as created_by, fo.created_at,
               (SELECT COUNT(*) FROM sheets s WHERE s.folder_id = fo.id AND s.is_active = TRUE) as sheet_count
        FROM folders fo
        LEFT JOIN users u ON fo.created_by = u.id
        WHERE fo.is_active = TRUE AND fo.created_by = $1
        ORDER BY fo.name ASC
      `, [req.user.id]);
    }
    res.json({ success: true, folders: foldersResult.rows });
  } catch (error) {
    console.error('Get sheet folders error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to get folders' } });
  }
});

// POST /sheets/folders - Create a folder for Sheets module
router.post('/folders', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { name, parent_id } = req.body;
    const normalizedParentId =
      parent_id === undefined || parent_id === null || String(parent_id).trim() === ''
        ? null
        : parseInt(parent_id, 10);

    const isDebugFolderCreate =
      process.env.DEBUG_FOLDER_CREATE === 'true' ||
      process.env.NODE_ENV !== 'production';

    if (isDebugFolderCreate) {
      console.log('[folders:create:sheet]', {
        name,
        parent_id: normalizedParentId,
        user_id: req.user.id,
      });
    }

    if (!name || !String(name).trim()) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Folder name is required' },
      });
    }

    if (normalizedParentId !== null && (Number.isNaN(normalizedParentId) || normalizedParentId <= 0)) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Invalid parent_id' },
      });
    }

    if (normalizedParentId !== null) {
      const isAdmin = req.user.role === 'admin';
      const parentFolder = await pool.query(
        `SELECT id
         FROM folders
         WHERE id = $1
           AND is_active = TRUE
           AND ($2::boolean = TRUE OR created_by = $3)`,
        [normalizedParentId, isAdmin, req.user.id]
      );

      if (parentFolder.rows.length === 0) {
        return res.status(404).json({
          success: false,
          error: { code: 'NOT_FOUND', message: 'Parent folder not found' },
        });
      }
    }

    const result = await pool.query(
      `INSERT INTO folders (name, parent_id, created_by)
       VALUES ($1, $2, $3)
       RETURNING id, name, parent_id, created_by, created_at, updated_at`,
      [String(name).trim(), normalizedParentId, req.user.id]
    );

    res.status(201).json({
      success: true,
      folder: result.rows[0],
    });
  } catch (error) {
    console.error('Create sheet folder error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to create sheet folder' },
    });
  }
});

// PUT /sheets/folders/:folderId/set-password - Set or remove a folder password (Admin/Editor)
router.put('/folders/:folderId/set-password', authenticate, async (req, res) => {
  try {
    if (!['admin', 'editor'].includes(req.user.role)) {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Only admins and editors can set folder passwords' } });
    }
    const { folderId } = req.params;
    const { password } = req.body;
    const passwordHash = (password && password.trim().length > 0)
      ? await bcrypt.hash(password.trim(), 10)
      : null;
    const result = await pool.query(
      `UPDATE folders SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 AND is_active = TRUE RETURNING id, name`,
      [passwordHash, folderId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Folder not found' } });
    }
    res.json({ success: true, message: password ? 'Folder password set' : 'Folder password removed', has_password: !!passwordHash });
  } catch (error) {
    console.error('Set folder password error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to set folder password' } });
  }
});

// POST /sheets/folders/:folderId/verify-password - Verify folder password
router.post('/folders/:folderId/verify-password', authenticate, async (req, res) => {
  try {
    const { folderId } = req.params;
    const { password } = req.body;
    const result = await pool.query(
      `SELECT password_hash FROM folders WHERE id = $1 AND is_active = TRUE`,
      [folderId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Folder not found' } });
    }
    const { password_hash } = result.rows[0];
    if (!password_hash) return res.json({ success: true }); // No password set
    const valid = await bcrypt.compare(password || '', password_hash);
    if (!valid) {
      return res.status(401).json({ success: false, error: { code: 'WRONG_PASSWORD', message: 'Incorrect password' } });
    }
    res.json({ success: true });
  } catch (error) {
    console.error('Verify folder password error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to verify folder password' } });
  }
});

// GET /sheets/edit-requests/all  – Admin: all edit requests across every sheet
// NOTE: must be declared BEFORE /:id routes so Express doesn't treat
//       'edit-requests' as a sheet id.
router.get('/edit-requests/all', authenticate, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Admin only' } });
    }

    const { status } = req.query;
    let query = `
      SELECT er.*, u.username  AS requester_username,
             rv.username AS reviewer_username,
             s.name      AS sheet_name
      FROM edit_requests er
      LEFT JOIN users  u  ON er.requested_by = u.id
      LEFT JOIN users  rv ON er.reviewed_by  = rv.id
      LEFT JOIN sheets s  ON er.sheet_id     = s.id
    `;
    const params = [];
    if (status) {
      params.push(status);
      query += ` WHERE er.status = $1`;
    }
    query += ' ORDER BY er.requested_at DESC';

    const result = await pool.query(query, params);
    res.json({ success: true, requests: result.rows });
  } catch (err) {
    console.error('Get all edit requests error:', err);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to get edit requests' } });
  }
});

// POST /sheets/:id/active-users/heartbeat - Upsert caller as active for this sheet
router.post('/:id/active-users/heartbeat', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const sheetId = parseInt(req.params.id, 10);
    if (Number.isNaN(sheetId) || sheetId <= 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'BAD_REQUEST', message: 'Invalid sheet id' }
      });
    }

    await pool.query(`
      INSERT INTO active_users (user_id, sheet_id, last_active_timestamp)
      VALUES ($1, $2, CURRENT_TIMESTAMP)
      ON CONFLICT (user_id, sheet_id)
      DO UPDATE SET last_active_timestamp = EXCLUDED.last_active_timestamp
    `, [req.user.id, sheetId]);

    res.json({
      success: true,
      message: 'Active user heartbeat updated',
      sheet_id: sheetId,
      user_id: req.user.id,
      server_time: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Active users heartbeat error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update active user heartbeat' }
    });
  }
});

// GET /sheets/:id/active-users - List active users in this sheet (last 10 seconds)
router.get('/:id/active-users', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const sheetId = parseInt(req.params.id, 10);
    if (Number.isNaN(sheetId) || sheetId <= 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'BAD_REQUEST', message: 'Invalid sheet id' }
      });
    }

    const result = await pool.query(`
      SELECT
        au.user_id,
        au.sheet_id,
        au.last_active_timestamp,
        u.username,
        u.full_name,
        r.name AS role,
        d.name AS department_name
      FROM active_users au
      INNER JOIN users u ON u.id = au.user_id
      LEFT JOIN roles r ON r.id = u.role_id
      LEFT JOIN departments d ON d.id = u.department_id
      WHERE au.sheet_id = $1
        AND au.last_active_timestamp > CURRENT_TIMESTAMP - INTERVAL '10 seconds'
      ORDER BY au.last_active_timestamp DESC
    `, [sheetId]);

    res.json({
      success: true,
      sheet_id: sheetId,
      total_active_users: result.rows.length,
      users: result.rows,
      server_time: new Date().toISOString(),
    });
  } catch (error) {
    console.error('Get active users error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get active users' }
    });
  }
});

// GET /sheets/:id - Get sheet data
router.get('/:id', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Get sheet info with lock and editing status
    const sheetResult = await pool.query(`
      SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
             s.created_at, s.updated_at, s.last_edited_by, le.username as last_edited_by_name,
             s.shown_to_viewers, s.grid_meta, sl.locked_by, lu.username as locked_by_name, sl.locked_at,
             ses.user_id as editing_user_id, seu.username as editing_user_name
      FROM sheets s
      LEFT JOIN users u ON s.created_by = u.id
      LEFT JOIN users le ON s.last_edited_by = le.id
      LEFT JOIN sheet_locks sl ON s.id = sl.sheet_id AND sl.expires_at > CURRENT_TIMESTAMP
      LEFT JOIN users lu ON sl.locked_by = lu.id
      LEFT JOIN sheet_edit_sessions ses ON s.id = ses.sheet_id AND ses.is_active = TRUE AND ses.last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
      LEFT JOIN users seu ON ses.user_id = seu.id
      WHERE s.id = $1 AND s.is_active = TRUE
    `, [id]);

    if (sheetResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    const sheet = sheetResult.rows[0];

    // Get sheet data
    const dataResult = await pool.query(`
      SELECT row_number, data
      FROM sheet_data
      WHERE sheet_id = $1
      ORDER BY row_number
    `, [id]);

    const rows = dataResult.rows.map(r => r.data);

    res.json({
      success: true,
      sheet: {
        ...sheet,
        rows: rows
      }
    });
  } catch (error) {
    console.error('Get sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get sheet' }
    });
  }
});

// POST /sheets - Create new sheet (User, Editor, Admin only)
router.post('/', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { name, columns } = req.body;

    const result = await pool.query(`
      INSERT INTO sheets (name, columns, created_by, last_edited_by)
      VALUES ($1, $2, $3, $3)
      RETURNING id, name, columns, created_by, created_at, updated_at
    `, [name, JSON.stringify(columns || ['A', 'B', 'C', 'D', 'E']), req.user.id]);

    const sheet = result.rows[0];

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'CREATE',
      entityType: 'sheets',
      entityId: sheet.id,
      metadata: { name }
    });

    res.status(201).json({
      success: true,
      sheet: sheet
    });
  } catch (error) {
    console.error('Create sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to create sheet' }
    });
  }
});

// PUT /sheets/:id - Update sheet (User, Editor, Admin only)
router.put('/:id', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, columns, rows, grid_meta } = req.body;

    // Inventory Tracker: allow direct edits only within the last 3 days.
    // Older DATE:* cells require an approved, unexpired edit request.
    const invDateRegex = /^DATE:(\d{4}-\d{2}-\d{2}):(IN|OUT)$/;
    const isInventoryTracker = Array.isArray(columns)
      ? columns.some((c) => typeof c === 'string' && invDateRegex.test(c))
      : false;
    const inventoryEditWindowDaysRaw = Number.parseInt(
      String(process.env.INVENTORY_EDIT_WINDOW_DAYS ?? '3'),
      10,
    );
    const inventoryEditWindowDays =
      Number.isFinite(inventoryEditWindowDaysRaw) && inventoryEditWindowDaysRaw > 0
        ? inventoryEditWindowDaysRaw
        : 3;
    const isAdmin = req.user.role === 'admin';

    // Check if sheet is locked by another user
    const lockCheck = await pool.query(`
      SELECT sl.locked_by, u.username 
      FROM sheet_locks sl
      LEFT JOIN users u ON sl.locked_by = u.id
      WHERE sl.sheet_id = $1 AND sl.expires_at > CURRENT_TIMESTAMP
    `, [id]);

    if (lockCheck.rows.length > 0 && lockCheck.rows[0].locked_by !== req.user.id && req.user.role !== 'admin') {
      return res.status(409).json({
        success: false,
        error: { 
          code: 'SHEET_LOCKED', 
          message: `Sheet is currently being edited by ${lockCheck.rows[0].username}` 
        }
      });
    }

    // Check sheet exists and get old data for comparison
    const sheetCheck = await pool.query(
      'SELECT id, created_by, name, columns FROM sheets WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (sheetCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    const oldSheet = sheetCheck.rows[0];

    // Get existing data for comparison
    const oldDataResult = await pool.query(
      'SELECT row_number, data FROM sheet_data WHERE sheet_id = $1 ORDER BY row_number',
      [id]
    );
    const oldData = oldDataResult.rows;

    // Update sheet metadata with last editor
    const gridMetaJson = grid_meta === undefined ? null : JSON.stringify(grid_meta ?? {});
    await pool.query(`
      UPDATE sheets
      SET name = $1,
          columns = $2,
          grid_meta = COALESCE($3::jsonb, grid_meta),
          last_edited_by = $4,
          updated_at = CURRENT_TIMESTAMP
      WHERE id = $5
    `, [name, JSON.stringify(columns), gridMetaJson, req.user.id, id]);

    // Track column renames
    const oldColumns = oldSheet.columns;
    const newColumns = columns;
    if (JSON.stringify(oldColumns) !== JSON.stringify(newColumns)) {
      await pool.query(`
        INSERT INTO sheet_edit_history (sheet_id, action, old_value, new_value, edited_by)
        VALUES ($1, 'RENAME_COLUMN', $2, $3, $4)
      `, [id, JSON.stringify(oldColumns), JSON.stringify(newColumns), req.user.id]);
    }

    // Merge-only update to avoid overwriting other users' recent edits.
    // Instead of deleting all rows, patch only changed cells into JSONB.
    const oldByRowNumber = new Map();
    for (const r of oldData) {
      oldByRowNumber.set(Number(r.row_number), r.data || {});
    }

    if (rows && rows.length > 0) {
      for (let i = 0; i < rows.length; i++) {
        const rowNumber = i + 1;
        const newRow = rows[i] || {};
        const oldRow = oldByRowNumber.get(rowNumber) || {};

        // Build a patch of only changed keys
        const patch = {};
        for (const col in newRow) {
          const newVal = newRow[col];
          const oldVal = oldRow[col];
          if (newVal !== oldVal) {
            patch[col] = newVal;
          }
        }

        const changedCols = Object.keys(patch);
        if (changedCols.length === 0) continue;

        // Track cell changes
        for (const col of changedCols) {
          // Enforce Inventory Tracker historical locks on the server.
          if (!isAdmin && isInventoryTracker && invDateRegex.test(col)) {
            const dateStr = col.split(':')[1];
            const parts = (dateStr || '').split('-').map((x) => Number.parseInt(x, 10));
            if (parts.length === 3 && parts.every((n) => Number.isFinite(n))) {
              const [yy, mm, dd] = parts;
              const cellDate = new Date(yy, mm - 1, dd);
              const now = new Date();
              const todayMidnight = new Date(now.getFullYear(), now.getMonth(), now.getDate());
              const earliestEditable = new Date(todayMidnight);
              earliestEditable.setDate(earliestEditable.getDate() - (inventoryEditWindowDays - 1));

              const isLockedByAge = cellDate.getTime() < earliestEditable.getTime();
              if (isLockedByAge) {
                const approval = await pool.query(
                  `SELECT 1
                   FROM edit_requests
                   WHERE sheet_id = $1
                     AND row_number = $2
                     AND column_name = $3
                     AND requested_by = $4
                     AND status = 'approved'
                     AND expires_at IS NOT NULL
                     AND expires_at > CURRENT_TIMESTAMP
                   ORDER BY reviewed_at DESC
                   LIMIT 1`,
                  [id, rowNumber, col, req.user.id]
                );

                if (approval.rows.length === 0) {
                  return res.status(403).json({
                    success: false,
                    error: {
                      code: 'FORBIDDEN',
                      message: `Cell ${col} (row ${rowNumber}) is older than ${inventoryEditWindowDays} days. Submit an edit request for admin approval.`,
                    },
                  });
                }
              }
            }
          }

          const oldVal = oldRow[col];
          const newVal = patch[col];
          if (newVal !== oldVal && (newVal || oldVal)) {
            await pool.query(`
              INSERT INTO sheet_edit_history (sheet_id, row_number, column_name, old_value, new_value, edited_by, action)
              VALUES ($1, $2, $3, $4, $5, $6, 'UPDATE')
            `, [id, rowNumber, col, oldVal || null, newVal || null, req.user.id]);
          }
        }

        await pool.query(`
          INSERT INTO sheet_data (sheet_id, row_number, data)
          VALUES ($1, $2, $3::jsonb)
          ON CONFLICT (sheet_id, row_number)
          DO UPDATE SET
            data       = sheet_data.data || EXCLUDED.data,
            updated_at = CURRENT_TIMESTAMP
        `, [id, rowNumber, JSON.stringify(patch)]);
      }
    }

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'UPDATE',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { name, rowCount: rows?.length || 0, edited_by: req.user.username }
    });

    // Auto-save to Files module
    try {
      const existingFile = await pool.query(
        'SELECT id FROM files WHERE source_sheet_id = $1 AND is_active = TRUE',
        [id]
      );

      if (existingFile.rows.length > 0) {
        // Update existing linked file
        const fileId = existingFile.rows[0].id;
        await pool.query(
          `UPDATE files SET name = $1, columns = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3`,
          [name, JSON.stringify(columns), fileId]
        );
        // Replace file_data
        await pool.query('DELETE FROM file_data WHERE file_id = $1', [fileId]);
        if (rows && rows.length > 0) {
          for (let i = 0; i < rows.length; i++) {
            await pool.query(
              'INSERT INTO file_data (file_id, row_number, data) VALUES ($1, $2, $3)',
              [fileId, i + 1, JSON.stringify(rows[i])]
            );
          }
        }
      } else {
        // Create new linked file
        const newFile = await pool.query(
          `INSERT INTO files (name, file_type, department_id, created_by, columns, source_sheet_id)
           VALUES ($1, 'xlsx', $2, $3, $4, $5) RETURNING id`,
          [name, req.user.department_id, req.user.id, JSON.stringify(columns), id]
        );
        const fileId = newFile.rows[0].id;
        if (rows && rows.length > 0) {
          for (let i = 0; i < rows.length; i++) {
            await pool.query(
              'INSERT INTO file_data (file_id, row_number, data) VALUES ($1, $2, $3)',
              [fileId, i + 1, JSON.stringify(rows[i])]
            );
          }
        }
      }
    } catch (fileSaveError) {
      console.error('Auto-save to files error (non-blocking):', fileSaveError);
      // Don't fail the sheet save if file auto-save fails
    }

    // ── Notify all users currently viewing this sheet that a full save occurred ──
    // This lets viewers refresh their local state without polling.
    try {
      const io = req.app.get('io');
      if (io) {
        io.to(`sheet-${id}`).emit('sheet_saved', {
          sheet_id:    parseInt(id),
          saved_by:    req.user.username,
          saved_by_id: req.user.id,
          columns,
          timestamp:   new Date().toISOString()
        });
      }
    } catch (broadcastErr) {
      // Non-blocking
      console.error('sheet_saved broadcast error:', broadcastErr.message);
    }

    res.json({
      success: true,
      message: 'Sheet updated successfully'
    });
  } catch (error) {
    console.error('Update sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update sheet' }
    });
  }
});

// DELETE /sheets/folders/:id - Delete a sheet folder (Admin only)
router.delete('/folders/:id', authenticate, requireRole('admin'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const folderId = parseInt(id);
    if (isNaN(folderId)) return res.status(400).json({ success: false, error: { code: 'INVALID_ID', message: 'Invalid folder ID' } });

    await client.query('BEGIN');

    // Hard-delete all sheets inside this folder (cascades to sheet_data, etc.)
    await client.query('DELETE FROM sheets WHERE folder_id = $1', [folderId]);

    // Hard-delete the folder itself
    await client.query('DELETE FROM folders WHERE id = $1', [folderId]);

    await client.query('COMMIT');

    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'folders',
      entityId: folderId,
      metadata: { deleted_by: req.user.username }
    });

    res.json({ success: true, message: 'Folder and all its sheets deleted' });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Delete sheet folder error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to delete folder' } });
  } finally {
    client.release();
  }
});

// DELETE /sheets/:id - Delete sheet and all its data (Admin only)
router.delete('/:id', authenticate, requireRole('admin'), async (req, res) => {
  const client = await pool.connect();
  try {
    const { id } = req.params;
    const sheetId = parseInt(id);
    if (isNaN(sheetId)) return res.status(400).json({ success: false, error: { code: 'INVALID_ID', message: 'Invalid sheet ID' } });

    await client.query('BEGIN');

    // Fetch sheet name for the audit log before deleting
    const sheetRes = await client.query('SELECT name FROM sheets WHERE id = $1', [sheetId]);
    if (!sheetRes.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Sheet not found' } });
    }
    const sheetName = sheetRes.rows[0].name;

    // Hard delete – cascades to: sheet_data, sheet_locks, sheet_edit_sessions,
    //   sheet_edit_history, edit_requests, active_users.
    // audit_logs.sheet_id is SET NULL so the audit trail is preserved.
    await client.query('DELETE FROM sheets WHERE id = $1', [sheetId]);

    await client.query('COMMIT');

    // Audit log (recorded after commit so the delete is permanent)
    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'sheets',
      entityId: sheetId,
      metadata: { deleted_by: req.user.username, sheet_name: sheetName }
    });

    res.json({ success: true, message: 'Sheet and all associated data deleted successfully' });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Delete sheet error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to delete sheet' } });
  } finally {
    client.release();
  }
});

// PATCH /sheets/:id/rename - Rename a sheet (Admin, Editor only)
router.patch('/:id/rename', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { name } = req.body;

    if (!name || !name.trim()) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Sheet name is required' }
      });
    }

    // Check if sheet exists
    const existingSheet = await pool.query(
      'SELECT id, name FROM sheets WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (existingSheet.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    const oldName = existingSheet.rows[0].name;

    // Update the sheet name
    const result = await pool.query(
      `UPDATE sheets SET name = $1, updated_at = CURRENT_TIMESTAMP
       WHERE id = $2 AND is_active = TRUE
       RETURNING id, name, columns, created_by, created_at, updated_at`,
      [name.trim(), id]
    );

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'RENAME',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { old_name: oldName, new_name: name.trim() }
    });

    res.json({
      success: true,
      sheet: result.rows[0]
    });
  } catch (error) {
    console.error('Rename sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to rename sheet' }
    });
  }
});

// PUT /sheets/:id/move - Move sheet to folder
router.put('/:id/move', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { folder_id } = req.body;

    // Check if sheet exists
    const sheetCheck = await pool.query(
      'SELECT id, name FROM sheets WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (sheetCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    // If folder_id is provided, verify folder exists
    if (folder_id !== null && folder_id !== undefined) {
      const folderCheck = await pool.query(
        'SELECT id FROM folders WHERE id = $1 AND is_active = TRUE',
        [folder_id]
      );

      if (folderCheck.rows.length === 0) {
        return res.status(404).json({
          success: false,
          error: { code: 'NOT_FOUND', message: 'Folder not found' }
        });
      }
    }

    // Move sheet to folder (null means root)
    await pool.query(
      'UPDATE sheets SET folder_id = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2',
      [folder_id || null, id]
    );

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'MOVE',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { 
        folder_id: folder_id || null,
        sheet_name: sheetCheck.rows[0].name 
      }
    });

    res.json({
      success: true,
      message: 'Sheet moved successfully'
    });
  } catch (error) {
    console.error('Move sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to move sheet' }
    });
  }
});

// GET /sheets/:id/history - Get edit history for a sheet
router.get('/:id/history', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const offset = (page - 1) * limit;

    // Check sheet exists
    const sheetCheck = await pool.query('SELECT id FROM sheets WHERE id = $1', [id]);
    if (sheetCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    const historyResult = await pool.query(`
      SELECT 
        h.id, h.sheet_id, h.row_number, h.column_name,
        h.old_value, h.new_value, h.action, h.edited_at,
        u.username as edited_by_name, u.full_name as edited_by_full_name
      FROM sheet_edit_history h
      LEFT JOIN users u ON h.edited_by = u.id
      WHERE h.sheet_id = $1
      ORDER BY h.edited_at DESC
      LIMIT $2 OFFSET $3
    `, [id, limit, offset]);

    const countResult = await pool.query(
      'SELECT COUNT(*) as total FROM sheet_edit_history WHERE sheet_id = $1',
      [id]
    );

    const total = parseInt(countResult.rows[0]?.total || 0);

    res.json({
      success: true,
      history: historyResult.rows,
      pagination: {
        page,
        limit,
        total,
        pages: Math.ceil(total / limit)
      }
    });
  } catch (error) {
    console.error('Get sheet history error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get sheet history' }
    });
  }
});

// GET /sheets/:id/export - Export sheet to Excel
router.get('/:id/export', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const format = req.query.format || 'xlsx'; // xlsx or csv

    // Get sheet info
    const sheetResult = await pool.query(`
      SELECT s.id, s.name, s.columns, s.created_by
      FROM sheets s
      WHERE s.id = $1 AND s.is_active = TRUE
    `, [id]);

    if (sheetResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    const sheet = sheetResult.rows[0];

    // Get all sheet data
    const dataResult = await pool.query(`
      SELECT row_number, data
      FROM sheet_data
      WHERE sheet_id = $1
      ORDER BY row_number
    `, [id]);

    const columns = sheet.columns;
    let rows = dataResult.rows.map(r => r.data);

    rows = rows.filter(row => {
      const values = columns.map(col => row[col] || '');
      const isHeaderRow = values.filter(v => v).length > 0 && 
                          values.every((val, idx) => {
                            return val === columns[idx] || val === '';
                          }) &&
                          values.some((val, idx) => val === columns[idx]);
      return !isHeaderRow;
    });

    const normalizeFormat = String(format || 'xlsx').toLowerCase();

    // CSV export stays simple.
    if (normalizeFormat === 'csv') {
      // ── Detect Inventory Tracker (has DATE:YYYY-MM-DD:IN columns) ──
      const invDateRegex = /^DATE:(\d{4}-\d{2}-\d{2}):(IN|OUT)$/;
      const isInventoryTracker = columns.some(col => invDateRegex.test(col));

      let wsData;

      if (isInventoryTracker) {
        const frozenLeft = columns.filter(col => ['Material Name', 'Product Name', 'QC Code', 'QB Code', 'Stock', 'Maintaining Qty', 'Maintaining Unit', 'Maintaining', 'Critical'].includes(col));
        const frozenRight = columns.filter(col => col === 'Total Quantity');
        const dates = [...new Set(
          columns
            .filter(col => /^DATE:\d{4}-\d{2}-\d{2}:IN$/.test(col))
            .map(col => col.split(':')[1])
        )].sort();

        const fmtDate = (d) => {
          const dt = new Date(d + 'T00:00:00');
          return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
        };

        const headerRow1 = [
          ...frozenLeft,
          ...dates.flatMap(d => [fmtDate(d), '']),
          ...frozenRight,
        ];
        const headerRow2 = [
          ...frozenLeft.map(() => ''),
          ...dates.flatMap(() => ['IN', 'OUT']),
          ...frozenRight.map(() => ''),
        ];

        wsData = [headerRow1, headerRow2];
        rows.forEach(row => {
          const rowArr = [
            ...frozenLeft.map(col => row[col] || ''),
            ...dates.flatMap(d => [row[`DATE:${d}:IN`] || '', row[`DATE:${d}:OUT`] || '']),
            ...frozenRight.map(col => row[col] || ''),
          ];
          wsData.push(rowArr);
        });
      } else {
        wsData = [];
        wsData.push(columns);
        rows.forEach(row => {
          const rowArray = columns.map(col => row[col] || '');
          wsData.push(rowArray);
        });
      }

      const csvText = toCsv(wsData);
      const fileBuffer = Buffer.from(csvText, 'utf8');
      const fileName = `${sheet.name.replace(/[^a-zA-Z0-9]/g, '_')}.csv`;
      res.setHeader('Content-Type', 'text/csv');
      res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
      res.send(fileBuffer);

      await auditService.log({
        userId: req.user.id,
        action: 'EXPORT',
        entityType: 'sheets',
        entityId: parseInt(id),
        metadata: { format: 'csv', name: sheet.name }
      });
      return;
    }

    // Styled XLSX export (ExcelJS)
    const wb = new ExcelJS.Workbook();
    wb.creator = 'Sales System';
    wb.created = new Date();
    const ws = wb.addWorksheet(sheet.name.substring(0, 31));

    const headerFill1 = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FF1F2937' } }; // dark
    const headerFill2 = { type: 'pattern', pattern: 'solid', fgColor: { argb: 'FFF3F4F6' } }; // light
    const headerFont1 = { bold: true, color: { argb: 'FFFFFFFF' } };
    const headerFont2 = { bold: true, color: { argb: 'FF111827' } };
    const thinBorder = {
      top: { style: 'thin', color: { argb: 'FFE5E7EB' } },
      left: { style: 'thin', color: { argb: 'FFE5E7EB' } },
      bottom: { style: 'thin', color: { argb: 'FFE5E7EB' } },
      right: { style: 'thin', color: { argb: 'FFE5E7EB' } },
    };

    // ── Detect Inventory Tracker (has DATE:YYYY-MM-DD:IN columns) ──
    const invDateRegex = /^DATE:(\d{4}-\d{2}-\d{2}):(IN|OUT)$/;
    const isInventoryTracker = columns.some(col => invDateRegex.test(col));

    const applyBorders = (rowNumber, colCount) => {
      for (let c = 1; c <= colCount; c++) {
        const cell = ws.getRow(rowNumber).getCell(c);
        cell.border = thinBorder;
      }
    };

    if (isInventoryTracker) {
      const frozenLeft = columns.filter(col => ['Material Name', 'Product Name', 'QC Code', 'QB Code', 'Stock', 'Maintaining Qty', 'Maintaining Unit', 'Maintaining', 'Critical'].includes(col));
      const frozenRight = columns.filter(col => col === 'Total Quantity');
      const dates = [...new Set(
        columns
          .filter(col => /^DATE:\d{4}-\d{2}-\d{2}:IN$/.test(col))
          .map(col => col.split(':')[1])
      )].sort();

      const fmtDate = (d) => {
        const dt = new Date(d + 'T00:00:00');
        return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      };

      const headerRow1 = [
        ...frozenLeft,
        ...dates.flatMap(d => [fmtDate(d), '']),
        ...frozenRight,
      ];
      const headerRow2 = [
        ...frozenLeft.map(() => ''),
        ...dates.flatMap(() => ['IN', 'OUT']),
        ...frozenRight.map(() => ''),
      ];

      ws.addRow(headerRow1);
      ws.addRow(headerRow2);

      // Data rows
      rows.forEach(row => {
        const rowArr = [
          ...frozenLeft.map(col => row[col] || ''),
          ...dates.flatMap(d => [row[`DATE:${d}:IN`] || '', row[`DATE:${d}:OUT`] || '']),
          ...frozenRight.map(col => row[col] || ''),
        ];
        ws.addRow(rowArr);
      });

      const totalCols = headerRow1.length;

      // Merges across date headers (row 1)
      let colIdx = frozenLeft.length + 1; // 1-based
      for (let i = 0; i < dates.length; i++) {
        ws.mergeCells(1, colIdx, 1, colIdx + 1);
        colIdx += 2;
      }

      // Styling header rows
      const r1 = ws.getRow(1);
      r1.height = 22;
      r1.eachCell({ includeEmpty: true }, (cell) => {
        cell.fill = headerFill1;
        cell.font = headerFont1;
        cell.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
      });
      applyBorders(1, totalCols);

      const r2 = ws.getRow(2);
      r2.height = 18;
      r2.eachCell({ includeEmpty: true }, (cell) => {
        cell.fill = headerFill2;
        cell.font = headerFont2;
        cell.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
      });
      applyBorders(2, totalCols);

      // Column widths
      const widths = [
        ...frozenLeft.map(() => 18),
        ...dates.flatMap(() => [10, 10]),
        ...frozenRight.map(() => 16),
      ];
      ws.columns = widths.map((w) => ({ width: w }));

      // Freeze top 2 rows + frozen left columns
      ws.views = [{ state: 'frozen', xSplit: frozenLeft.length, ySplit: 2 }];
    } else {
      // Standard sheet: header row + data
      ws.addRow(columns);
      rows.forEach(row => {
        ws.addRow(columns.map(col => row[col] || ''));
      });

      const totalCols = columns.length;
      const r1 = ws.getRow(1);
      r1.height = 22;
      r1.eachCell({ includeEmpty: true }, (cell) => {
        cell.fill = headerFill1;
        cell.font = headerFont1;
        cell.alignment = { vertical: 'middle', horizontal: 'center', wrapText: true };
      });
      applyBorders(1, totalCols);

      // Basic widths
      ws.columns = columns.map(() => ({ width: 18 }));
      ws.views = [{ state: 'frozen', ySplit: 1 }];
    }

    // Generate buffer
    const fileBuffer = await wb.xlsx.writeBuffer();

    // Set headers
    const fileName = `${sheet.name.replace(/[^a-zA-Z0-9]/g, '_')}.xlsx`;
    const mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

    res.setHeader('Content-Type', mimeType);
    res.setHeader('Content-Disposition', `attachment; filename="${fileName}"`);
    res.send(fileBuffer);

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'EXPORT',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { format, name: sheet.name }
    });
  } catch (error) {
    console.error('Export sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to export sheet' }
    });
  }
});

// POST /sheets/:id/import - Import data from Excel/CSV (User, Editor, Admin only)
router.post('/:id/import', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { data: importData } = req.body; // Array of arrays or base64 file

    // Check role permissions
    if (!['admin', 'manager', 'editor'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'You do not have permission to import data' }
      });
    }

    // Check sheet exists
    const sheetCheck = await pool.query(
      'SELECT id, name FROM sheets WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (sheetCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    let rows;
    let columns;

    // If data is provided directly (array of arrays)
    if (Array.isArray(importData) && importData.length > 0) {
      columns = importData[0]; // First row is headers
      rows = importData.slice(1).map(row => {
        const rowObj = {};
        columns.forEach((col, idx) => {
          rowObj[col] = row[idx] !== undefined ? String(row[idx]) : '';
        });
        return rowObj;
      });
    } else {
      return res.status(400).json({
        success: false,
        error: { code: 'INVALID_DATA', message: 'Invalid import data format' }
      });
    }

    // Update sheet with imported data
    await pool.query(`
      UPDATE sheets SET columns = $1, updated_at = CURRENT_TIMESTAMP
      WHERE id = $2
    `, [JSON.stringify(columns), id]);

    // Delete existing data
    await pool.query('DELETE FROM sheet_data WHERE sheet_id = $1', [id]);

    // Insert imported data
    for (let i = 0; i < rows.length; i++) {
      await pool.query(`
        INSERT INTO sheet_data (sheet_id, row_number, data)
        VALUES ($1, $2, $3)
      `, [id, i + 1, JSON.stringify(rows[i])]);
    }

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'IMPORT',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { rowCount: rows.length, columnCount: columns.length }
    });

    res.json({
      success: true,
      message: 'Data imported successfully',
      rowCount: rows.length,
      columnCount: columns.length
    });
  } catch (error) {
    console.error('Import sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to import data' }
    });
  }
});

// PUT /sheets/:id/visibility - Toggle sheet visibility to viewers (Admin or Editor)
router.put('/:id/visibility', authenticate, async (req, res) => {
  try {
    if (!['admin', 'editor'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Only admins and editors can control sheet visibility' }
      });
    }

    const { id } = req.params;
    const { shown_to_viewers } = req.body;

    // Update sheet visibility
    const result = await pool.query(`
      UPDATE sheets SET shown_to_viewers = $1, updated_at = CURRENT_TIMESTAMP
      WHERE id = $2 AND is_active = TRUE
      RETURNING id, name, shown_to_viewers
    `, [shown_to_viewers, id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: shown_to_viewers ? 'SHOW_TO_VIEWERS' : 'HIDE_FROM_VIEWERS',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { 
        sheet_name: result.rows[0].name,
        shown_to_viewers: shown_to_viewers
      }
    });

    res.json({
      success: true,
      message: `Sheet ${shown_to_viewers ? 'shown to' : 'hidden from'} viewers`,
      sheet: result.rows[0]
    });

  } catch (error) {
    console.error('Update sheet visibility error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update sheet visibility' }
    });
  }
});

// PUT /sheets/:id/set-password - Set or remove a sheet password (Admin/Editor)
router.put('/:id/set-password', authenticate, async (req, res) => {
  try {
    if (!['admin', 'editor'].includes(req.user.role)) {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Only admins and editors can set sheet passwords' } });
    }
    const { id } = req.params;
    const { password } = req.body;
    const passwordHash = (password && password.trim().length > 0)
      ? await bcrypt.hash(password.trim(), 10)
      : null;
    const result = await pool.query(
      `UPDATE sheets SET password_hash = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2 AND is_active = TRUE RETURNING id, name`,
      [passwordHash, id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Sheet not found' } });
    }
    await auditService.log({
      userId: req.user.id,
      action: password ? 'SET_PASSWORD' : 'REMOVE_PASSWORD',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { sheet_name: result.rows[0].name }
    });
    res.json({ success: true, message: password ? 'Sheet password set' : 'Sheet password removed', has_password: !!passwordHash });
  } catch (error) {
    console.error('Set sheet password error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to set sheet password' } });
  }
});

// POST /sheets/:id/verify-password - Verify sheet password
router.post('/:id/verify-password', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const { password } = req.body;
    const result = await pool.query(
      `SELECT password_hash FROM sheets WHERE id = $1 AND is_active = TRUE`,
      [id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Sheet not found' } });
    }
    const { password_hash } = result.rows[0];
    if (!password_hash) return res.json({ success: true }); // No password set
    const valid = await bcrypt.compare(password || '', password_hash);
    if (!valid) {
      return res.status(401).json({ success: false, error: { code: 'WRONG_PASSWORD', message: 'Incorrect password' } });
    }
    res.json({ success: true });
  } catch (error) {
    console.error('Verify sheet password error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to verify sheet password' } });
  }
});

// POST /sheets/:id/lock - Lock sheet for editing
router.post('/:id/lock', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { id } = req.params;
    
    // Check if sheet exists
    const sheetCheck = await pool.query(
      'SELECT id, name FROM sheets WHERE id = $1 AND is_active = TRUE',
      [id]
    );
    
    if (sheetCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    // Check for existing lock
    const existingLock = await pool.query(`
      SELECT sl.locked_by, u.username 
      FROM sheet_locks sl
      LEFT JOIN users u ON sl.locked_by = u.id
      WHERE sl.sheet_id = $1 AND sl.expires_at > CURRENT_TIMESTAMP
    `, [id]);

    if (existingLock.rows.length > 0 && existingLock.rows[0].locked_by !== req.user.id) {
      return res.status(409).json({
        success: false,
        error: { 
          code: 'SHEET_LOCKED', 
          message: `Sheet is locked by ${existingLock.rows[0].username}` 
        }
      });
    }

    // Create or update lock (30 minute expiry)
    await pool.query(`
      INSERT INTO sheet_locks (sheet_id, locked_by, expires_at)
      VALUES ($1, $2, CURRENT_TIMESTAMP + INTERVAL '30 minutes')
      ON CONFLICT (sheet_id) 
      DO UPDATE SET 
        locked_by = $2, 
        locked_at = CURRENT_TIMESTAMP,
        expires_at = CURRENT_TIMESTAMP + INTERVAL '30 minutes'
    `, [id, req.user.id]);

    // Start edit session
    await pool.query(`
      INSERT INTO sheet_edit_sessions (sheet_id, user_id, is_active)
      VALUES ($1, $2, TRUE)
      ON CONFLICT (sheet_id, user_id) 
      DO UPDATE SET 
        last_activity = CURRENT_TIMESTAMP,
        is_active = TRUE
    `, [id, req.user.id]);

    res.json({
      success: true,
      message: 'Sheet locked successfully',
      locked_by: req.user.username,
      expires_in_minutes: 30
    });

  } catch (error) {
    console.error('Lock sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to lock sheet' }
    });
  }
});

// DELETE /sheets/:id/lock - Unlock sheet
router.delete('/:id/lock', authenticate, async (req, res) => {
  try {
    const { id } = req.params;

    // Remove lock (only by the user who locked it or admin)
    const result = await pool.query(`
      DELETE FROM sheet_locks 
      WHERE sheet_id = $1 AND (locked_by = $2 OR $3 = 'admin')
      RETURNING locked_by
    `, [id, req.user.id, req.user.role]);

    // End edit session
    await pool.query(`
      UPDATE sheet_edit_sessions 
      SET is_active = FALSE 
      WHERE sheet_id = $1 AND user_id = $2
    `, [id, req.user.id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'No lock found or permission denied' }
      });
    }

    res.json({
      success: true,
      message: 'Sheet unlocked successfully'
    });

  } catch (error) {
    console.error('Unlock sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to unlock sheet' }
    });
  }
});

// POST /sheets/:id/edit-session - Start/update edit session
router.post('/:id/edit-session', authenticate, requireSheetEditAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Update edit session heartbeat
    await pool.query(`
      INSERT INTO sheet_edit_sessions (sheet_id, user_id, is_active, last_activity)
      VALUES ($1, $2, TRUE, CURRENT_TIMESTAMP)
      ON CONFLICT (sheet_id, user_id) 
      DO UPDATE SET 
        last_activity = CURRENT_TIMESTAMP,
        is_active = TRUE
    `, [id, req.user.id]);

    res.json({
      success: true,
      message: 'Edit session updated'
    });

  } catch (error) {
    console.error('Update edit session error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update edit session' }
    });
  }
});

// GET /sheets/:id/status - Get current sheet status (locks/editors)
router.get('/:id/status', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Get current lock status
    const lockResult = await pool.query(`
      SELECT sl.locked_by, u.username as locked_by_name, sl.locked_at, sl.expires_at
      FROM sheet_locks sl
      LEFT JOIN users u ON sl.locked_by = u.id
      WHERE sl.sheet_id = $1 AND sl.expires_at > CURRENT_TIMESTAMP
    `, [id]);

    // Get active editors
    const editorsResult = await pool.query(`
      SELECT ses.user_id, u.username, ses.last_activity
      FROM sheet_edit_sessions ses
      LEFT JOIN users u ON ses.user_id = u.id
      WHERE ses.sheet_id = $1 AND ses.is_active = TRUE 
        AND ses.last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
      ORDER BY ses.last_activity DESC
    `, [id]);

    const lock = lockResult.rows.length > 0 ? lockResult.rows[0] : null;
    const activeEditors = editorsResult.rows;

    res.json({
      success: true,
      status: {
        is_locked: lock !== null,
        locked_by: lock ? lock.locked_by_name : null,
        locked_at: lock ? lock.locked_at : null,
        expires_at: lock ? lock.expires_at : null,
        active_editors: activeEditors,
        total_active_editors: activeEditors.length
      }
    });

  } catch (error) {
    console.error('Get sheet status error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get sheet status' }
    });
  }
});

// ============================================================
//  Edit Requests (Admin Approval Workflow for Locked Cells)
// ============================================================

// GET /sheets/:id/edit-requests  – Admin sees all requests for a sheet
router.get('/:id/edit-requests', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const { status } = req.query; // optional filter: pending | approved | rejected

    if (req.user.role !== 'admin') {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Admin only' } });
    }

    let query = `
      SELECT er.*, u.username as requester_username,
             rv.username as reviewer_username,
             s.name as sheet_name
      FROM edit_requests er
      LEFT JOIN users u  ON er.requested_by = u.id
      LEFT JOIN users rv ON er.reviewed_by  = rv.id
      LEFT JOIN sheets s ON er.sheet_id     = s.id
      WHERE er.sheet_id = $1
    `;
    const params = [id];
    if (status) {
      params.push(status);
      query += ` AND er.status = $${params.length}`;
    }
    query += ' ORDER BY er.requested_at DESC';

    const result = await pool.query(query, params);
    res.json({ success: true, requests: result.rows });
  } catch (err) {
    console.error('Get edit requests error:', err);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to get edit requests' } });
  }
});

// POST /sheets/:id/edit-requests  – Editor submits a request
router.post('/:id/edit-requests', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const { row_number, column_name, cell_reference, current_value, proposed_value } = req.body;

    if (req.user.role === 'viewer') {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Viewers cannot submit edit requests' } });
    }

    // Inventory Tracker guard: do not accept OUT values that would make totals negative.
    // (Defense-in-depth; clients should validate too.)
    if (String(proposed_value ?? '').trim() !== '') {
      const validation = await inventoryDateQtyEditWouldBeInvalid({
        sheetId: id,
        rowNumber: row_number,
        columnName: column_name,
        proposedValue: proposed_value,
      });
      if (validation.invalid) {
        return res.status(400).json({
          success: false,
          error: {
            code: 'INVALID_VALUE',
            message: validation.reason || 'Invalid value',
          },
        });
      }
    }

    // Cancel duplicate pending request for same cell by same user
    await pool.query(`
      DELETE FROM edit_requests
      WHERE sheet_id = $1 AND row_number = $2 AND column_name = $3
        AND requested_by = $4 AND status = 'pending'
    `, [id, row_number, column_name, req.user.id]);

    // Fetch user's department name
    const deptResult = await pool.query(`
      SELECT d.name FROM users u LEFT JOIN departments d ON u.department_id = d.id WHERE u.id = $1
    `, [req.user.id]);
    const deptName = deptResult.rows[0]?.name || null;

    const result = await pool.query(`
      INSERT INTO edit_requests
        (sheet_id, row_number, column_name, cell_reference, current_value,
         proposed_value, requested_by, requester_role, requester_dept, status)
      VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'pending')
      RETURNING *
    `, [id, row_number, column_name, cell_reference || null, current_value || null,
        proposed_value || null, req.user.id, req.user.role, deptName]);

    // Notify all online admins + anyone in the sheet room via socket.
    const collab = req.app.get('collab');
    if (collab) {
      collab.io.to(`sheet-${id}`).to('admins').emit('edit_request_notification', {
        request_id:     result.rows[0].id,
        sheet_id:       parseInt(id),
        row_number,
        column_name,
        cell_ref:       cell_reference || null,
        current_value:  current_value  || null,
        proposed_value: proposed_value || null,
        requested_by:   req.user.username,
        requester_role: req.user.role,
        requester_dept: deptName,
        requested_at:   result.rows[0].requested_at,
      });
    }

    res.status(201).json({ success: true, request: result.rows[0] });
  } catch (err) {
    console.error('Submit edit request error:', err);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to submit edit request' } });
  }
});

// PUT /sheets/:id/edit-requests/:reqId  – Admin approves or rejects
router.put('/:id/edit-requests/:reqId', authenticate, async (req, res) => {
  try {
    const { id, reqId } = req.params;
    const { approved, reject_reason } = req.body;

    if (req.user.role !== 'admin') {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Admin only' } });
    }

    // Load pending request so we can validate before writing an approval.
    const pendingRes = await pool.query(
      'SELECT * FROM edit_requests WHERE id = $1 AND sheet_id = $2 AND status = \'pending\'',
      [reqId, id]
    );
    if (pendingRes.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Request not found or already resolved' } });
    }

    let finalApproved = Boolean(approved);
    let finalRejectReason = reject_reason || null;

    const pendingReq = pendingRes.rows[0];
    if (
      finalApproved &&
      pendingReq.proposed_value !== null &&
      pendingReq.proposed_value !== undefined
    ) {
      const validation = await inventoryDateQtyEditWouldBeInvalid({
        sheetId: pendingReq.sheet_id,
        rowNumber: pendingReq.row_number,
        columnName: pendingReq.column_name,
        proposedValue: pendingReq.proposed_value,
      });
      if (validation.invalid) {
        finalApproved = false;
        finalRejectReason = validation.reason || 'Invalid value';
      }
    }

    const status     = finalApproved ? 'approved' : 'rejected';
    const expiresAt  = finalApproved ? new Date(Date.now() + 10 * 60 * 1000) : null;

    const result = await pool.query(`
      UPDATE edit_requests
      SET status        = $2,
          reviewed_by   = $3,
          reviewed_at   = CURRENT_TIMESTAMP,
          reject_reason = $4,
          expires_at    = $5
      WHERE id = $1 AND sheet_id = $6 AND status = 'pending'
      RETURNING *
    `, [reqId, status, req.user.id, finalRejectReason, expiresAt, id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Request not found or already resolved' } });
    }

    // Emit real-time events so the editor gets notified even when the admin
    // resolves via the REST API instead of through the WebSocket flow.
    const collab = req.app.get('collab');
    if (collab) {
      try {
        await collab.emitResolveEvents(
          result.rows[0],
          finalApproved,
          finalRejectReason,
          req.user.username,
        );
      } catch (emitErr) {
        console.error('emitResolveEvents failed:', emitErr);
        // Non-fatal: the DB status update succeeded. Don't fail the HTTP request.
      }
    }

    res.json({ success: true, request: result.rows[0] });
  } catch (err) {
    console.error('Resolve edit request error:', err);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to resolve edit request' } });
  }
});

// DELETE /sheets/edit-requests/:reqId  – Admin deletes a resolved (approved/rejected) edit request
router.delete('/edit-requests/:reqId', authenticate, async (req, res) => {
  try {
    const { reqId } = req.params;

    if (req.user.role !== 'admin') {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Admin only' } });
    }

    const result = await pool.query(`
      DELETE FROM edit_requests
      WHERE id = $1 AND status != 'pending'
      RETURNING id
    `, [reqId]);

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Request not found or still pending — only resolved requests can be deleted' } });
    }

    res.json({ success: true, message: 'Edit request deleted.' });
  } catch (err) {
    console.error('Delete edit request error:', err);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to delete edit request' } });
  }
});

// GET /sheets/:id/audit  – Sheet-level cell audit trail (admin + editor)
router.get('/:id/audit', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 50, cell_reference } = req.query;
    const offset = (parseInt(page) - 1) * parseInt(limit);

    if (!['admin', 'editor'].includes(req.user.role)) {
      return res.status(403).json({ success: false, error: { code: 'FORBIDDEN', message: 'Admin or editor only' } });
    }

    let baseWhere = 'WHERE al.sheet_id = $1';
    const params = [id];

    if (cell_reference) {
      params.push(cell_reference);
      baseWhere += ` AND al.cell_reference = $${params.length}`;
    }

    const result = await pool.query(`
      SELECT al.id, al.action, al.cell_reference, al.field_name,
             al.old_value, al.new_value, al.created_at,
             al.role, al.department_name,
             u.username, u.full_name
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      ${baseWhere}
      ORDER BY al.created_at DESC
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `, [...params, parseInt(limit), offset]);

    const countResult = await pool.query(
      `SELECT COUNT(*) as total FROM audit_logs al ${baseWhere}`, params
    );

    res.json({
      success: true,
      logs: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: parseInt(countResult.rows[0].total)
      }
    });
  } catch (err) {
    console.error('Sheet audit error:', err);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to get sheet audit' } });
  }
});

module.exports = router;
