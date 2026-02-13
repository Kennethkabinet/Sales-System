const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { 
  requireSheetAccess, 
  requireSheetEditAccess,
  requireRole 
} = require('../middleware/rbac');
const auditService = require('../services/auditService');
const XLSX = require('xlsx');

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

    if (req.user.role === 'admin') {
      // Admin sees all sheets
      query = `
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
        WHERE s.is_active = TRUE
        ORDER BY s.updated_at DESC
        LIMIT $1 OFFSET $2
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE`;
      params = [limit, offset];
      countParams = [];
    } else if (req.user.role === 'viewer') {
      // Viewers only see sheets shown to them by admin
      query = `
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
        WHERE s.is_active = TRUE AND s.shown_to_viewers = TRUE
        ORDER BY s.updated_at DESC
        LIMIT $1 OFFSET $2
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE AND shown_to_viewers = TRUE`;
      params = [limit, offset];
      countParams = [];
    } else if (req.user.role === 'editor') {
      // Editors see all sheets (they need access to edit any sheet)
      query = `
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
        WHERE s.is_active = TRUE
        ORDER BY s.updated_at DESC
        LIMIT $1 OFFSET $2
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE`;
      params = [limit, offset];
      countParams = [];
    } else {
      // Regular users see their own sheets or shared sheets
      query = `
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
        WHERE s.is_active = TRUE AND (s.created_by = $1 OR s.is_shared = TRUE)
        ORDER BY s.updated_at DESC
        LIMIT $2 OFFSET $3
      `;
      countQuery = `SELECT COUNT(*) as total FROM sheets WHERE is_active = TRUE AND (created_by = $1 OR is_shared = TRUE)`;
      params = [req.user.id, limit, offset];
      countParams = [req.user.id];
    }

    const [sheetsResult, countResult] = await Promise.all([
      pool.query(query, params),
      pool.query(countQuery, countParams)
    ]);

    const total = parseInt(countResult.rows[0]?.total || 0);

    res.json({
      success: true,
      sheets: sheetsResult.rows,
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

    // Get sheet data
    const dataResult = await pool.query(`
      SELECT row_number, data
      FROM sheet_data
      WHERE sheet_id = $1
      ORDER BY row_number
    `, [id]);

    // Prepare data for SheetJS
    const columns = sheet.columns;
    const rows = dataResult.rows.map(r => r.data);

    // Create workbook
    const wb = XLSX.utils.book_new();
    
    // Convert to array format for SheetJS
    const wsData = [];
    // Add header row
    wsData.push(columns);
    // Add data rows
    rows.forEach(row => {
      const rowArray = columns.map(col => row[col] || '');
      wsData.push(rowArray);
    });

    // Create worksheet
    const ws = XLSX.utils.aoa_to_sheet(wsData);
    XLSX.utils.book_append_sheet(wb, ws, sheet.name.substring(0, 31)); // Excel sheet name limit

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

// PUT /sheets/:id/visibility - Toggle sheet visibility to viewers (Admin only)
router.put('/:id/visibility', authenticate, async (req, res) => {
  try {
    if (req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Only admins can control sheet visibility' }
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

module.exports = router;
