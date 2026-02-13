const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');

// GET /dashboard/stats - Get dashboard statistics
router.get('/stats', authenticate, async (req, res) => {
  try {
    let departmentFilter = '';
    const params = [];
    
    // Non-admins see only their department
    if (req.user.role !== 'admin') {
      params.push(req.user.department_id);
      departmentFilter = 'WHERE department_id = $1';
    }
    
    // Get total sales (sum of 'total' column from all file data)
    const salesResult = await pool.query(`
      SELECT COALESCE(SUM((data->>'total')::numeric), 0) as total_sales
      FROM file_data fd
      JOIN files f ON fd.file_id = f.id
      ${departmentFilter.replace('department_id', 'f.department_id')}
    `, params);
    
    // Get total inventory (sum of 'quantity' column)
    const inventoryResult = await pool.query(`
      SELECT COALESCE(SUM((data->>'quantity')::numeric), 0) as total_inventory
      FROM file_data fd
      JOIN files f ON fd.file_id = f.id
      ${departmentFilter.replace('department_id', 'f.department_id')}
    `, params);
    
    // Get active users count
    const usersResult = await pool.query(`
      SELECT COUNT(*) as active_users FROM users 
      WHERE is_active = TRUE AND last_login > CURRENT_TIMESTAMP - INTERVAL '24 hours'
    `);
    
    // Get files count
    const filesResult = await pool.query(`
      SELECT COUNT(*) as files_count FROM files 
      WHERE is_active = TRUE ${departmentFilter ? 'AND ' + departmentFilter.replace('WHERE ', '') : ''}
    `, params);
    
    // Get formulas count
    const formulasResult = await pool.query(`
      SELECT COUNT(*) as formulas_count FROM formulas 
      WHERE is_active = TRUE ${req.user.role !== 'admin' ? 'AND (is_shared = TRUE OR created_by = $1 OR department_id = $2)' : ''}
    `, req.user.role !== 'admin' ? [req.user.id, req.user.department_id] : []);
    
    // Sales trend (last 7 days) - simulated based on audit logs
    const trendResult = await pool.query(`
      SELECT DATE(created_at) as date, COUNT(*) as changes
      FROM audit_logs
      WHERE created_at >= CURRENT_DATE - INTERVAL '7 days'
      GROUP BY DATE(created_at)
      ORDER BY date
    `);
    
    // Top products (if product data exists)
    const productsResult = await pool.query(`
      SELECT 
        data->>'product_name' as name,
        SUM((data->>'quantity')::numeric) as quantity,
        SUM((data->>'total')::numeric) as revenue
      FROM file_data fd
      JOIN files f ON fd.file_id = f.id
      WHERE data->>'product_name' IS NOT NULL
      ${departmentFilter ? 'AND ' + departmentFilter.replace('WHERE ', '').replace('department_id', 'f.department_id') : ''}
      GROUP BY data->>'product_name'
      ORDER BY revenue DESC NULLS LAST
      LIMIT 5
    `, params);
    
    // Department breakdown
    const deptResult = await pool.query(`
      SELECT d.name as department, 
             COUNT(DISTINCT f.id) as file_count,
             ROUND(COUNT(DISTINCT f.id)::numeric / NULLIF((SELECT COUNT(*) FROM files WHERE is_active = TRUE), 0) * 100, 1) as percentage
      FROM departments d
      LEFT JOIN files f ON d.id = f.department_id AND f.is_active = TRUE
      GROUP BY d.id, d.name
      ORDER BY file_count DESC
    `);
    
    res.json({
      success: true,
      stats: {
        total_sales: parseFloat(salesResult.rows[0]?.total_sales || 0),
        total_inventory: parseInt(inventoryResult.rows[0]?.total_inventory || 0),
        active_users: parseInt(usersResult.rows[0]?.active_users || 0),
        files_count: parseInt(filesResult.rows[0]?.files_count || 0),
        formulas_count: parseInt(formulasResult.rows[0]?.formulas_count || 0)
      },
      sales_trend: trendResult.rows.map(row => ({
        date: row.date,
        amount: parseInt(row.changes) * 1000 // Simulated amount for demo
      })),
      top_products: productsResult.rows.map(row => ({
        name: row.name,
        quantity: parseInt(row.quantity || 0),
        revenue: parseFloat(row.revenue || 0)
      })),
      department_breakdown: deptResult.rows.map(row => ({
        department: row.department,
        percentage: parseFloat(row.percentage || 0)
      }))
    });
    
  } catch (error) {
    console.error('Get dashboard stats error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get dashboard stats' }
    });
  }
});

// GET /dashboard/recent-activity - Get recent activity
router.get('/recent-activity', authenticate, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 10;
    
    let query = `
      SELECT u.username, al.action, f.name as file_name, al.field_name,
             al.old_value, al.new_value, al.created_at as timestamp
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
    `;
    
    const params = [];
    
    if (req.user.role !== 'admin') {
      params.push(req.user.department_id);
      query += ` WHERE f.department_id = $1`;
    }
    
    query += ` ORDER BY al.created_at DESC LIMIT $${params.length + 1}`;
    params.push(limit);
    
    const result = await pool.query(query, params);
    
    res.json({
      success: true,
      activity: result.rows
    });
    
  } catch (error) {
    console.error('Get recent activity error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get recent activity' }
    });
  }
});

// GET /dashboard/active-editors - Get currently active file editors
router.get('/active-editors', authenticate, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT DISTINCT u.username, f.name as file_name, rl.locked_at
      FROM row_locks rl
      JOIN users u ON rl.locked_by = u.id
      JOIN files f ON rl.file_id = f.id
      WHERE rl.expires_at > CURRENT_TIMESTAMP
      ORDER BY rl.locked_at DESC
    `);
    
    res.json({
      success: true,
      editors: result.rows
    });
    
  } catch (error) {
    console.error('Get active editors error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get active editors' }
    });
  }
});

module.exports = router;
