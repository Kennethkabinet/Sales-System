const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { requireAdminAccess } = require('../middleware/rbac');

// GET /dashboard/stats - Get dashboard statistics (Admin only)
router.get('/stats', authenticate, requireAdminAccess, async (req, res) => {
  try {
    // Admin has access to all data across all departments
    
    // Get total sales (sum of 'total' column from all file data)
    const salesResult = await pool.query(`
      SELECT COALESCE(SUM((data->>'total')::numeric), 0) as total_sales
      FROM file_data fd
      JOIN files f ON fd.file_id = f.id
    `);
    
    // Get total inventory (sum of 'quantity' column)
    const inventoryResult = await pool.query(`
      SELECT COALESCE(SUM((data->>'quantity')::numeric), 0) as total_inventory
      FROM file_data fd
      JOIN files f ON fd.file_id = f.id
    `);
    
    // Get active users count
    const usersResult = await pool.query(`
      SELECT COUNT(*) as active_users FROM users 
      WHERE is_active = TRUE
    `);
    
    // Get active users list with details
    const activeUsersListResult = await pool.query(`
      SELECT u.id, u.username, u.full_name, u.email, r.name as role, u.last_login
      FROM users u
      LEFT JOIN roles r ON u.role_id = r.id
      WHERE u.is_active = TRUE
      ORDER BY u.last_login DESC NULLS LAST
    `);
    
    // Get files count
    const filesResult = await pool.query(`
      SELECT COUNT(*) as files_count FROM files 
      WHERE is_active = TRUE
    `);
    
    // Get formulas count
    const formulasResult = await pool.query(`
      SELECT COUNT(*) as formulas_count FROM formulas 
      WHERE is_active = TRUE
    `);
    
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
      GROUP BY data->>'product_name'
      ORDER BY revenue DESC NULLS LAST
      LIMIT 5
    `);
    
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
      active_users_list: activeUsersListResult.rows.map(row => ({
        id: row.id,
        username: row.username,
        full_name: row.full_name,
        email: row.email,
        role: row.role || 'user',
        last_login: row.last_login
      })),
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

// GET /dashboard/recent-activity - Get recent activity (Admin only)
router.get('/recent-activity', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 10;
    
    // Admin sees all activity across all departments
    const query = `
      SELECT u.username, al.action, f.name as file_name, al.field_name,
             al.old_value, al.new_value, al.created_at as timestamp
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
      ORDER BY al.created_at DESC LIMIT $1
    `;
    
    const result = await pool.query(query, [limit]);
    
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

// GET /dashboard/active-editors - Get currently active file editors (Admin only)
router.get('/active-editors', authenticate, requireAdminAccess, async (req, res) => {
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
