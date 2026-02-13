const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const auditService = require('../services/auditService');

// GET /sheets - Get all sheets for user
router.get('/', authenticate, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 50;
    const offset = (page - 1) * limit;

    let query;
    let countQuery;
    let params;
    let countParams;

    if (req.user.role === 'admin' || req.user.role === 'manager') {
      // Admin and managers see all sheets
      query = `
        SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
               s.created_at, s.updated_at
        FROM sheets s
        LEFT JOIN users u ON s.created_by = u.id
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
               s.created_at, s.updated_at
        FROM sheets s
        LEFT JOIN users u ON s.created_by = u.id
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
router.get('/:id', authenticate, async (req, res) => {
  try {
    const { id } = req.params;

    // Get sheet info
    const sheetResult = await pool.query(`
      SELECT s.id, s.name, s.columns, s.created_by, u.username as created_by_name,
             s.created_at, s.updated_at
      FROM sheets s
      LEFT JOIN users u ON s.created_by = u.id
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

// POST /sheets - Create new sheet
router.post('/', authenticate, async (req, res) => {
  try {
    const { name, columns } = req.body;

    // Check role permissions
    if (!['admin', 'manager', 'editor'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'You do not have permission to create sheets' }
      });
    }

    const result = await pool.query(`
      INSERT INTO sheets (name, columns, created_by)
      VALUES ($1, $2, $3)
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

// PUT /sheets/:id - Update sheet
router.put('/:id', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, columns, rows } = req.body;

    // Check role permissions
    if (!['admin', 'manager', 'editor'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'You do not have permission to edit sheets' }
      });
    }

    // Check sheet exists
    const sheetCheck = await pool.query(
      'SELECT id, created_by FROM sheets WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (sheetCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Sheet not found' }
      });
    }

    // Update sheet metadata
    await pool.query(`
      UPDATE sheets SET name = $1, columns = $2, updated_at = CURRENT_TIMESTAMP
      WHERE id = $3
    `, [name, JSON.stringify(columns), id]);

    // Delete existing data and insert new data
    await pool.query('DELETE FROM sheet_data WHERE sheet_id = $1', [id]);

    if (rows && rows.length > 0) {
      for (let i = 0; i < rows.length; i++) {
        await pool.query(`
          INSERT INTO sheet_data (sheet_id, row_number, data)
          VALUES ($1, $2, $3)
        `, [id, i + 1, JSON.stringify(rows[i])]);
      }
    }

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'UPDATE',
      entityType: 'sheets',
      entityId: parseInt(id),
      metadata: { name, rowCount: rows?.length || 0 }
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

// DELETE /sheets/:id - Delete sheet
router.delete('/:id', authenticate, async (req, res) => {
  try {
    const { id } = req.params;

    // Check role permissions
    if (!['admin', 'manager'].includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'You do not have permission to delete sheets' }
      });
    }

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
      metadata: {}
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

module.exports = router;
