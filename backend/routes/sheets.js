const express = require('express');
const router = express.Router();
const pool = require('../db');
const multer = require('multer');
const { authenticate } = require('../middleware/auth');
const { 
  requireSheetAccess, 
  requireSheetEditAccess,
  requireRole 
} = require('../middleware/rbac');
const auditService = require('../services/auditService');
const XLSX = require('xlsx');
const bcrypt = require('bcrypt');

// Multer memory storage for sheet file imports
const uploadMemory = multer({ storage: multer.memoryStorage(), limits: { fileSize: 20 * 1024 * 1024 } });

// Self-healing migration: add password_hash columns for folder/sheet password protection
pool.query(`
  ALTER TABLE sheets ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
  ALTER TABLE folders ADD COLUMN IF NOT EXISTS password_hash VARCHAR(255);
`).catch(err => console.error('[Migration] password_hash columns:', err.message));

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
      // Editors and regular users see folders they own
      folderQuery = `SELECT fo.id, fo.name, fo.parent_id, u.username as created_by, fo.created_at, fo.updated_at,
              (SELECT COUNT(*) FROM sheets s2 WHERE s2.folder_id = fo.id AND s2.is_active = TRUE) as sheet_count
       FROM folders fo LEFT JOIN users u ON fo.created_by = u.id
       WHERE fo.is_active = TRUE AND ${parentCondition} AND fo.created_by = $${fpIdx}
       ORDER BY fo.name ASC`;
      if (folderIdParam !== undefined && folderIdParam !== 'root' && folderIdParam !== '') {
        folderQueryParams.push(parseInt(folderIdParam));
      }
      folderQueryParams.push(req.user.id);
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

    // Parse with XLSX (supports xlsx, xls, csv)
    const workbook = XLSX.read(req.file.buffer, { type: 'buffer' });
    const firstSheetName = workbook.SheetNames[0];
    const worksheet = workbook.Sheets[firstSheetName];
    const rawData = XLSX.utils.sheet_to_json(worksheet, { header: 1, defval: '' });

    if (!rawData || rawData.length === 0) {
      return res.status(400).json({ success: false, error: { code: 'EMPTY_FILE', message: 'The file appears to be empty' } });
    }

    // First row = column headers
    const columns = (rawData[0] || []).map((c, i) => c ? String(c) : `Column${i + 1}`);
    const dataRows = rawData.slice(1).map(row => {
      const rowObj = {};
      columns.forEach((col, idx) => {
        rowObj[col] = row[idx] !== undefined ? String(row[idx]) : '';
      });
      return rowObj;
    });

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

// GET /sheets/:id - Get sheet data
router.get('/:id', authenticate, requireSheetAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Get sheet info with lock and editing status
    const sheetResult = await pool.query(`
      SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
             s.created_at, s.updated_at, s.last_edited_by, le.username as last_edited_by_name,
             s.shown_to_viewers, sl.locked_by, lu.username as locked_by_name, sl.locked_at,
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
    const { name, columns, rows } = req.body;

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
    await pool.query(`
      UPDATE sheets SET name = $1, columns = $2, last_edited_by = $3, updated_at = CURRENT_TIMESTAMP
      WHERE id = $4
    `, [name, JSON.stringify(columns), req.user.id, id]);

    // Track column renames
    const oldColumns = oldSheet.columns;
    const newColumns = columns;
    if (JSON.stringify(oldColumns) !== JSON.stringify(newColumns)) {
      await pool.query(`
        INSERT INTO sheet_edit_history (sheet_id, action, old_value, new_value, edited_by)
        VALUES ($1, 'RENAME_COLUMN', $2, $3, $4)
      `, [id, JSON.stringify(oldColumns), JSON.stringify(newColumns), req.user.id]);
    }

    // Delete existing data and insert new data
    await pool.query('DELETE FROM sheet_data WHERE sheet_id = $1', [id]);

    if (rows && rows.length > 0) {
      for (let i = 0; i < rows.length; i++) {
        const newRow = rows[i];
        const oldRow = oldData[i]?.data || {};
        
        // Track cell changes
        for (const col in newRow) {
          if (newRow[col] !== oldRow[col] && (newRow[col] || oldRow[col])) {
            await pool.query(`
              INSERT INTO sheet_edit_history (sheet_id, row_number, column_name, old_value, new_value, edited_by, action)
              VALUES ($1, $2, $3, $4, $5, $6, 'UPDATE')
            `, [id, i + 1, col, oldRow[col] || null, newRow[col] || null, req.user.id]);
          }
        }

        await pool.query(`
          INSERT INTO sheet_data (sheet_id, row_number, data)
          VALUES ($1, $2, $3)
        `, [id, i + 1, JSON.stringify(newRow)]);
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
  try {
    const { id } = req.params;

    // Move sheets in this folder back to root
    await pool.query('UPDATE sheets SET folder_id = NULL, updated_at = CURRENT_TIMESTAMP WHERE folder_id = $1', [id]);

    // Soft delete the folder
    await pool.query('UPDATE folders SET is_active = FALSE WHERE id = $1', [id]);

    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'folders',
      entityId: parseInt(id),
      metadata: { deleted_by: req.user.username }
    });

    res.json({ success: true, message: 'Folder deleted' });
  } catch (error) {
    console.error('Delete sheet folder error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to delete folder' } });
  }
});

// DELETE /sheets/:id - Delete sheet (Admin only)
router.delete('/:id', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { id } = req.params;

    // Soft delete
    await pool.query(
      'UPDATE sheets SET is_active = FALSE, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
      [id]
    );

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { deleted_by: req.user.username }
    });

    res.json({
      success: true,
      message: 'Sheet deleted successfully'
    });
  } catch (error) {
    console.error('Delete sheet error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to delete sheet' }
    });
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

    // Prepare data for SheetJS
    const columns = sheet.columns;
    let rows = dataResult.rows.map(r => r.data);

    // Filter out any row that exactly matches the column headers (A, B, C, D, etc.)
    rows = rows.filter(row => {
      const values = columns.map(col => row[col] || '');
      // Check if this row contains values that exactly match column names
      const isHeaderRow = values.filter(v => v).length > 0 && 
                          values.every((val, idx) => {
                            return val === columns[idx] || val === '';
                          }) &&
                          values.some((val, idx) => val === columns[idx]);
      return !isHeaderRow;
    });

    // Create workbook
    const wb = XLSX.utils.book_new();

    // ── Detect Inventory Tracker (has DATE:YYYY-MM-DD:IN columns) ──
    const invDateRegex = /^DATE:(\d{4}-\d{2}-\d{2}):(IN|OUT)$/;
    const isInventoryTracker = columns.some(col => invDateRegex.test(col));

    if (isInventoryTracker) {
      // Categorise columns
      const frozenLeft = columns.filter(col => ['Product Name', 'QC Code', 'Maintaining'].includes(col));
      const frozenRight = columns.filter(col => col === 'Total Quantity');
      const dates = [...new Set(
        columns
          .filter(col => /^DATE:\d{4}-\d{2}-\d{2}:IN$/.test(col))
          .map(col => col.split(':')[1])
      )].sort();

      // Helper: format date as "Feb-17"
      const fmtDate = (d) => {
        const dt = new Date(d + 'T00:00:00');
        return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
      };

      // Row 1: Product Name | QC Code | Maintaining | Feb-17 | (blank) | Feb-18 | (blank) | ... | Total Quantity
      const headerRow1 = [
        ...frozenLeft,
        ...dates.flatMap(d => [fmtDate(d), '']),
        ...frozenRight,
      ];

      // Row 2: (blank per frozen left) | IN | OUT | IN | OUT | ... | (blank per frozen right)
      const headerRow2 = [
        ...frozenLeft.map(() => ''),
        ...dates.flatMap(() => ['IN', 'OUT']),
        ...frozenRight.map(() => ''),
      ];

      const wsData = [headerRow1, headerRow2];

      // Data rows
      rows.forEach(row => {
        const rowArr = [
          ...frozenLeft.map(col => row[col] || ''),
          ...dates.flatMap(d => [row[`DATE:${d}:IN`] || '', row[`DATE:${d}:OUT`] || '']),
          ...frozenRight.map(col => row[col] || ''),
        ];
        wsData.push(rowArr);
      });

      const ws = XLSX.utils.aoa_to_sheet(wsData);

      // Merge date group cells across IN/OUT pairs in row 1 (r=0)
      ws['!merges'] = [];
      let colIdx = frozenLeft.length;
      for (let i = 0; i < dates.length; i++) {
        ws['!merges'].push({ s: { r: 0, c: colIdx }, e: { r: 0, c: colIdx + 1 } });
        colIdx += 2;
      }

      // Column widths
      ws['!cols'] = [
        ...frozenLeft.map(() => ({ wch: 18 })),
        ...dates.flatMap(() => [{ wch: 10 }, { wch: 10 }]),
        ...frozenRight.map(() => ({ wch: 16 })),
      ];

      XLSX.utils.book_append_sheet(wb, ws, sheet.name.substring(0, 31));
    } else {
      // ── Standard export with column header row 1 ──
      const wsData = [];
      // Header row
      wsData.push(columns);
      // Data rows
      rows.forEach(row => {
        const rowArray = columns.map(col => row[col] || '');
        wsData.push(rowArray);
      });
      const ws = XLSX.utils.aoa_to_sheet(wsData);
      XLSX.utils.book_append_sheet(wb, ws, sheet.name.substring(0, 31));
    }

    // Generate buffer
    const fileBuffer = XLSX.write(wb, { type: 'buffer', bookType: format === 'csv' ? 'csv' : 'xlsx' });

    // Set headers
    const fileName = `${sheet.name.replace(/[^a-zA-Z0-9]/g, '_')}.${format === 'csv' ? 'csv' : 'xlsx'}`;
    const mimeType = format === 'csv' 
      ? 'text/csv' 
      : 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

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

    const status     = approved ? 'approved' : 'rejected';
    const expiresAt  = approved ? new Date(Date.now() + 10 * 60 * 1000) : null;

    const result = await pool.query(`
      UPDATE edit_requests
      SET status        = $2,
          reviewed_by   = $3,
          reviewed_at   = CURRENT_TIMESTAMP,
          reject_reason = $4,
          expires_at    = $5
      WHERE id = $1 AND sheet_id = $6 AND status = 'pending'
      RETURNING *
    `, [reqId, status, req.user.id, reject_reason || null, expiresAt, id]);

    if (result.rows.length === 0) {
      return res.status(404).json({ success: false, error: { code: 'NOT_FOUND', message: 'Request not found or already resolved' } });
    }

    // Emit real-time events so the editor gets notified even when the admin
    // resolves via the REST API instead of through the WebSocket flow.
    const collab = req.app.get('collab');
    if (collab) {
      collab.emitResolveEvents(result.rows[0], approved, reject_reason, req.user.username);
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
