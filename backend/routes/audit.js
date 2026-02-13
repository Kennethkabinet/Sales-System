const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { requireAdminAccess } = require('../middleware/rbac');

// GET /audit - Get audit logs (Admin only)
router.get('/', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { 
      file_id, user_id, action, entity_type,
      start_date, end_date,
      page = 1, limit = 50 
    } = req.query;
    
    const offset = (page - 1) * limit;
    
    // Build WHERE clause separately for count query
    let whereClause = ' WHERE 1=1';
    const params = [];
    
    // Non-admins can only see their own logs or their department logs
    if (req.user.role !== 'admin') {
      params.push(req.user.id, req.user.department_id);
      whereClause += ` AND (al.user_id = $${params.length - 1} OR f.department_id = $${params.length})`;
    }
    
    // Apply filters
    if (file_id) {
      params.push(file_id);
      whereClause += ` AND al.file_id = $${params.length}`;
    }
    
    if (user_id && req.user.role === 'admin') {
      params.push(user_id);
      whereClause += ` AND al.user_id = $${params.length}`;
    }
    
    if (action) {
      params.push(action);
      whereClause += ` AND al.action = $${params.length}`;
    }
    
    if (entity_type) {
      params.push(entity_type);
      whereClause += ` AND al.entity_type = $${params.length}`;
    }
    
    if (start_date) {
      params.push(start_date);
      whereClause += ` AND al.created_at >= $${params.length}`;
    }
    
    if (end_date) {
      params.push(end_date);
      whereClause += ` AND al.created_at <= $${params.length}`;
    }
    
    // Get total count
    const countQuery = `
      SELECT COUNT(*) as total
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
      ${whereClause}
    `;
    const countResult = await pool.query(countQuery, params);
    const total = parseInt(countResult.rows[0]?.total || 0);
    
    // Build full query with entity name resolution
    let query = `
      SELECT al.id, al.action, al.entity_type, al.entity_id,
             al.user_id, u.username, f.name as file_name,
             al.row_number, al.field_name, al.old_value, al.new_value,
             al.metadata, al.created_at,
             CASE 
               WHEN al.entity_type = 'users' THEN (SELECT COALESCE(eu.full_name, eu.username) FROM users eu WHERE eu.id::text = al.entity_id::text)
               WHEN al.entity_type = 'sheets' THEN (SELECT es.name FROM sheets es WHERE es.id::text = al.entity_id::text)
               WHEN al.entity_type = 'files' THEN (SELECT ef.name FROM files ef WHERE ef.id::text = al.entity_id::text)
               ELSE NULL
             END as entity_name
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
      ${whereClause}
    `;
    
    // Add ordering and pagination
    query += ` ORDER BY al.created_at DESC LIMIT $${params.length + 1} OFFSET $${params.length + 2}`;
    params.push(limit, offset);
    
    const result = await pool.query(query, params);
    
    res.json({
      success: true,
      logs: result.rows.map(log => ({
        id: log.id,
        user_id: log.user_id,
        username: log.username,
        action: log.action,
        entity_type: log.entity_type,
        entity_id: log.entity_id,
        entity_name: log.entity_name,
        file_name: log.file_name,
        row_number: log.row_number,
        field_name: log.field_name,
        old_value: log.old_value,
        new_value: log.new_value,
        metadata: log.metadata,
        timestamp: log.created_at
      })),
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit)
      }
    });
    
  } catch (error) {
    console.error('Get audit logs error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get audit logs' }
    });
  }
});

// GET /audit/summary - Get audit summary statistics
router.get('/summary', authenticate, requireAdminAccess, async (req, res) => {
  try {
    let baseFilter = '';
    const params = [];
    
    // Non-admins filter
    if (req.user.role !== 'admin') {
      params.push(req.user.id, req.user.department_id);
      baseFilter = `WHERE (al.user_id = $1 OR f.department_id = $2)`;
    }
    
    // Total changes
    const totalResult = await pool.query(`
      SELECT COUNT(*) as total FROM audit_logs al
      LEFT JOIN files f ON al.file_id = f.id
      ${baseFilter}
    `, params);
    
    // Today's changes
    const todayResult = await pool.query(`
      SELECT COUNT(*) as today FROM audit_logs al
      LEFT JOIN files f ON al.file_id = f.id
      ${baseFilter} ${baseFilter ? 'AND' : 'WHERE'} al.created_at >= CURRENT_DATE
    `, params);
    
    // This week's changes
    const weekResult = await pool.query(`
      SELECT COUNT(*) as this_week FROM audit_logs al
      LEFT JOIN files f ON al.file_id = f.id
      ${baseFilter} ${baseFilter ? 'AND' : 'WHERE'} al.created_at >= CURRENT_DATE - INTERVAL '7 days'
    `, params);
    
    // Changes by action
    const byActionResult = await pool.query(`
      SELECT al.action, COUNT(*) as count FROM audit_logs al
      LEFT JOIN files f ON al.file_id = f.id
      ${baseFilter}
      GROUP BY al.action
    `, params);
    
    const byAction = {};
    byActionResult.rows.forEach(row => {
      byAction[row.action] = parseInt(row.count);
    });
    
    // Changes by user (top 10)
    const byUserResult = await pool.query(`
      SELECT u.username, COUNT(*) as count FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
      ${baseFilter}
      GROUP BY u.username
      ORDER BY count DESC
      LIMIT 10
    `, params);
    
    // Recent activity (last 10)
    const recentResult = await pool.query(`
      SELECT u.username, al.action, f.name as file_name, al.created_at as timestamp
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
      ${baseFilter}
      ORDER BY al.created_at DESC
      LIMIT 10
    `, params);
    
    res.json({
      success: true,
      summary: {
        total_changes: parseInt(totalResult.rows[0]?.total || 0),
        today: parseInt(todayResult.rows[0]?.today || 0),
        this_week: parseInt(weekResult.rows[0]?.this_week || 0),
        by_action: byAction,
        by_user: byUserResult.rows.map(row => ({
          username: row.username,
          count: parseInt(row.count)
        })),
        recent_activity: recentResult.rows.map(row => ({
          username: row.username,
          action: row.action,
          file_name: row.file_name,
          timestamp: row.timestamp
        }))
      }
    });
    
  } catch (error) {
    console.error('Get audit summary error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get audit summary' }
    });
  }
});

// GET /audit/file/:fileId - Get audit logs for specific file
router.get('/file/:fileId', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { fileId } = req.params;
    const { page = 1, limit = 50 } = req.query;
    const offset = (page - 1) * limit;
    
    const result = await pool.query(`
      SELECT al.id, al.action, u.username, al.row_number, al.field_name,
             al.old_value, al.new_value, al.created_at
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      WHERE al.file_id = $1
      ORDER BY al.created_at DESC
      LIMIT $2 OFFSET $3
    `, [fileId, limit, offset]);
    
    const countResult = await pool.query(
      'SELECT COUNT(*) as total FROM audit_logs WHERE file_id = $1',
      [fileId]
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
    
  } catch (error) {
    console.error('Get file audit logs error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get file audit logs' }
    });
  }
});

// GET /audit/user/:userId - Get audit logs for specific user (Admin only)
router.get('/user/:userId', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { userId } = req.params;
    const { page = 1, limit = 50 } = req.query;
    const offset = (page - 1) * limit;
    
    const result = await pool.query(`
      SELECT al.id, al.action, al.entity_type, f.name as file_name,
             al.row_number, al.field_name, al.old_value, al.new_value, al.created_at
      FROM audit_logs al
      LEFT JOIN files f ON al.file_id = f.id
      WHERE al.user_id = $1
      ORDER BY al.created_at DESC
      LIMIT $2 OFFSET $3
    `, [userId, limit, offset]);
    
    const countResult = await pool.query(
      'SELECT COUNT(*) as total FROM audit_logs WHERE user_id = $1',
      [userId]
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
    
  } catch (error) {
    console.error('Get user audit logs error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get user audit logs' }
    });
  }
});

module.exports = router;
