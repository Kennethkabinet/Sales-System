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

// GET /dashboard/inventory-sheets – Returns list of active inventory tracker sheets (Admin only)
router.get('/inventory-sheets', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT id, name, created_at FROM sheets
      WHERE is_active = TRUE AND name ILIKE '%inventory%'
      ORDER BY created_at ASC
    `);
    res.json({ success: true, sheets: result.rows });
  } catch (error) {
    console.error('GET /dashboard/inventory-sheets error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to get inventory sheets' } });
  }
});

// GET /dashboard/inventory-overview – Reads from Inventory Tracker sheets (Admin only)
router.get('/inventory-overview', authenticate, requireAdminAccess, async (req, res) => {
  try {
    // ── 1. Resolve sheet IDs: use ?sheet_ids=43,52 if provided, else all inventory sheets ─
    // Accepts formats like "1,2", ["1","2"], [1,2], or "[1,2]".
    const parseSheetIds = (raw) => {
      if (raw == null) return [];

      let parts = [];
      if (Array.isArray(raw)) {
        parts = raw;
      } else if (typeof raw === 'string') {
        const text = raw.trim();
        if (!text) return [];
        if (text.startsWith('[') && text.endsWith(']')) {
          try {
            const parsed = JSON.parse(text);
            if (Array.isArray(parsed)) {
              parts = parsed;
            } else {
              parts = text.split(',');
            }
          } catch (_) {
            parts = text.split(',');
          }
        } else {
          parts = text.split(',');
        }
      } else {
        parts = [raw];
      }

      return [...new Set(
        parts
          .map(v => parseInt(v, 10))
          .filter(n => Number.isFinite(n) && n > 0)
      )];
    };

    let sheetIds;
    const hasSheetFilter = Object.prototype.hasOwnProperty.call(req.query, 'sheet_ids');
    if (hasSheetFilter) {
      sheetIds = parseSheetIds(req.query.sheet_ids);
    }

    if (!sheetIds) {
      const sheetsRes = await pool.query(`
        SELECT id FROM sheets
        WHERE is_active = TRUE AND name ILIKE '%inventory%'
        ORDER BY id ASC
      `);
      sheetIds = sheetsRes.rows.map(r => r.id);
    }

    const emptyResponse = {
      success: true,
      summary: {
        total_materials: 0,
        total_product_categories: 0,
        total_stock_qty: 0,
        low_stock_count: 0, out_of_stock_count: 0,
        total_purchases_this_month: 0, total_used_this_month: 0,
      },
      monthly_trend: [], category_breakdown: [],
      ink_breakdown: [], low_stock_items: [], product_stocks: [],
    };

    if (!sheetIds.length) return res.json(emptyResponse);

    // ── 2. Fetch all non-empty product rows from those sheets ───────────────
    const rowsRes = await pool.query(`
      SELECT sheet_id, data
      FROM sheet_data
      WHERE sheet_id = ANY($1)
        AND data->>'Product Name' IS NOT NULL
        AND TRIM(data->>'Product Name') != ''
      ORDER BY sheet_id ASC
    `, [sheetIds]);

    if (!rowsRes.rows.length) return res.json(emptyResponse);

    // ── 3. Process rows ─────────────────────────────────────────────────────
    // productMap: keyed by normalized product name + QB/QC code; values are summed across sheets
    const productMap = {};   // key → { name, qc_code, maintaining_qty, current_stock }
    const dateInMap  = {};   // "YYYY-MM-DD" → total qty IN
    const dateOutMap = {};   // "YYYY-MM-DD" → total qty OUT
    const productOutMap = {}; // key → total qty OUT (for ink breakdown)

    for (const row of rowsRes.rows) {
      const d = row.data;
      const name = (d['Product Name'] || '').trim();
      if (!name) continue;
      const code = (d['QB Code'] || d['QC Code'] || '').toString().trim();
      const productKey = `${name.toLowerCase()}|${code.toLowerCase()}`;

      const maintaining = parseFloat(d['Maintaining']) || 0;
      const totalQty    = parseFloat(d['Total Quantity']) || 0;

      // Aggregate product across sheets by product name + QB/QC code
      if (!productMap[productKey]) {
        productMap[productKey] = {
          name,
          qc_code: code,
          maintaining_qty: 0,
          current_stock: 0,
        };
        productOutMap[productKey] = 0;
      }
      productMap[productKey].maintaining_qty += maintaining;
      productMap[productKey].current_stock += totalQty;
      if (code && !productMap[productKey].qc_code) {
        productMap[productKey].qc_code = code;
      }

      // Accumulate date columns (DATE:YYYY-MM-DD:IN / OUT)
      for (const [key, val] of Object.entries(d)) {
        const m = key.match(/^DATE:(\d{4}-\d{2}-\d{2}):(IN|OUT)$/);
        if (!m) continue;
        const qty = parseFloat(val) || 0;
        if (qty <= 0) continue;

        const [, date, type] = m;
        if (type === 'IN') {
          dateInMap[date]  = (dateInMap[date]  || 0) + qty;
        } else {
          dateOutMap[date] = (dateOutMap[date] || 0) + qty;
          productOutMap[productKey] = (productOutMap[productKey] || 0) + qty;
        }
      }
    }

    const products = Object.values(productMap);

    // ── 4. Summary stats ────────────────────────────────────────────────────
    const now = new Date();
    const currentMonthPrefix = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;

    let totalPurchasesThisMonth = 0;
    let totalUsedThisMonth      = 0;
    for (const [date, qty] of Object.entries(dateInMap)) {
      if (date.startsWith(currentMonthPrefix)) totalPurchasesThisMonth += qty;
    }
    for (const [date, qty] of Object.entries(dateOutMap)) {
      if (date.startsWith(currentMonthPrefix)) totalUsedThisMonth += qty;
    }

    const summary = {
      total_materials:            products.length,
      total_stock_qty:            products.reduce((s, p) => s + p.current_stock, 0),
      low_stock_count:            products.filter(p => p.current_stock > 0 && p.maintaining_qty > 0 && p.current_stock <= p.maintaining_qty).length,
      out_of_stock_count:         products.filter(p => p.current_stock <= 0).length,
      total_purchases_this_month: Math.round(totalPurchasesThisMonth),
      total_used_this_month:      Math.round(totalUsedThisMonth),
    };

    // ── 5. Monthly trend ────────────────────────────────────────────────────
    const monthlyMap = {};
    const allDates = new Set([...Object.keys(dateInMap), ...Object.keys(dateOutMap)]);
    for (const date of allDates) {
      const month = date.substring(0, 7); // "YYYY-MM"
      if (!monthlyMap[month]) monthlyMap[month] = { stock_in: 0, stock_out: 0 };
      monthlyMap[month].stock_in  += (dateInMap[date]  || 0);
      monthlyMap[month].stock_out += (dateOutMap[date] || 0);
    }
    const monthlyTrend = Object.entries(monthlyMap)
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([month, v]) => {
        const d = new Date(month + '-02');
        const label = d.toLocaleDateString('en-US', { month: 'short', year: '2-digit' });
        return { month_label: label, stock_in: Math.round(v.stock_in), stock_out: Math.round(v.stock_out) };
      });

    // ── 6. Category breakdown ───────────────────────────────────────────────
    const categoryMap = {};
    for (const p of products) {
      const n = p.name.toLowerCase();
      const cat =
        /ink|cyan|magenta|yellow|black/.test(n)           ? 'Ink'        :
        /paper|bond|cardboard|sticker|art paper/.test(n)  ? 'Paper'      :
        /tarp|vinyl|mesh|canvas|backlit/.test(n)           ? 'Tarpaulin'  : 'Others';
      if (!categoryMap[cat]) categoryMap[cat] = { category: cat, material_count: 0, total_stock: 0 };
      categoryMap[cat].material_count++;
      categoryMap[cat].total_stock += p.current_stock;
    }
    const categoryBreakdown = Object.values(categoryMap).sort((a, b) => b.total_stock - a.total_stock);
    summary.total_product_categories = products.length;

    const productStocks = products
      .map(p => ({
        product_name: p.name,
        qc_code: p.qc_code,
        qb_code: p.qc_code,
        current_stock: Math.round(p.current_stock),
      }))
      .sort((a, b) => a.product_name.localeCompare(b.product_name));

    // ── 7. Ink consumption breakdown ────────────────────────────────────────
    const inkMap = {};
    for (const [productKey, totalOut] of Object.entries(productOutMap)) {
      if (totalOut <= 0) continue;
      const p = productMap[productKey];
      if (!p) continue;
      const name = p.name || '';
      const n = name.toLowerCase();
      const inkType =
        /cyan/.test(n)    ? 'Cyan'      :
        /magenta/.test(n) ? 'Magenta'   :
        /yellow/.test(n)  ? 'Yellow'    :
        /black/.test(n)   ? 'Black'     :
        /ink/.test(n)     ? 'Other Ink' : null;
      if (!inkType) continue;
      inkMap[inkType] = (inkMap[inkType] || 0) + totalOut;
    }
    const inkBreakdown = Object.entries(inkMap)
      .map(([ink_type, total_used]) => ({ ink_type, total_used: Math.round(total_used) }))
      .sort((a, b) => b.total_used - a.total_used);

    // ── 8. Low-stock alert list ─────────────────────────────────────────────
    const lowStockItems = products
      .filter(p => p.maintaining_qty > 0 && p.current_stock <= p.maintaining_qty)
      .sort((a, b) => a.current_stock - b.current_stock)
      .map((p, i) => ({
        id:              i + 1,
        product_name:    p.name,
        qc_code:         p.qc_code,
        qb_code:         p.qc_code,
        current_stock:   Math.round(p.current_stock),
        maintaining_qty: Math.round(p.maintaining_qty),
        critical_qty:    0,
        stock_status:    p.current_stock <= 0 ? 'critical' : 'warning',
      }));

    res.json({
      success: true,
      summary,
      monthly_trend: monthlyTrend,
      category_breakdown: categoryBreakdown,
      ink_breakdown: inkBreakdown,
      low_stock_items: lowStockItems,
      product_stocks: productStocks,
    });

  } catch (error) {
    console.error('GET /dashboard/inventory-overview error:', error);
    res.status(500).json({ success: false, error: { code: 'SERVER_ERROR', message: 'Failed to get inventory overview' } });
  }
});

module.exports = router;
