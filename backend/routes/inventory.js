const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const auditService = require('../services/auditService');

// ─── Helper: log inventory audit ─────────────────────────────────────────────
async function logInventoryAudit(client, { transactionId, productId, action, oldData, newData, userId }) {
  await client.query(
    `INSERT INTO inventory_audit_log (transaction_id, product_id, action, old_data, new_data, performed_by)
     VALUES ($1, $2, $3, $4, $5, $6)`,
    [transactionId, productId, action,
      oldData ? JSON.stringify(oldData) : null,
      newData ? JSON.stringify(newData) : null,
      userId]
  );
}

// ─── Helper: compute running stock up to a given date for a product ───────────
async function getStockBeforeDate(client, productId, date) {
  const res = await client.query(
    `SELECT COALESCE(SUM(qty_in), 0) - COALESCE(SUM(qty_out), 0) AS stock
     FROM inventory_transactions
     WHERE product_id = $1 AND transaction_date < $2`,
    [productId, date]
  );
  return parseInt(res.rows[0].stock, 10);
}

// =============================================================================
// PRODUCT MASTER ENDPOINTS
// =============================================================================

// GET /inventory/stock  – Current stock snapshot for all active products
router.get('/stock', authenticate, async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT * FROM product_stock_snapshot ORDER BY product_name`
    );
    res.json({ products: result.rows });
  } catch (err) {
    console.error('GET /inventory/stock error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  }
});

// GET /inventory/products  – All products (including inactive for admin)
router.get('/products', authenticate, async (req, res) => {
  try {
    const isAdmin = req.user.role === 'admin';
    const whereClause = isAdmin ? '' : 'WHERE p.is_active = TRUE';

    const result = await pool.query(
      `SELECT p.*,
              u.username AS created_by_name,
              ub.username AS updated_by_name
       FROM product_master p
       LEFT JOIN users u  ON u.id  = p.created_by
       LEFT JOIN users ub ON ub.id = p.updated_by
       ${whereClause}
       ORDER BY p.product_name`
    );
    res.json({ products: result.rows });
  } catch (err) {
    console.error('GET /inventory/products error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  }
});

// POST /inventory/products  (admin only)
router.post('/products', authenticate, requireRole(['admin']), async (req, res) => {
  const { product_name, qc_code, maintaining_qty = 0, critical_qty = 0 } = req.body;
  if (!product_name?.trim()) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'product_name is required' } });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const result = await client.query(
      `INSERT INTO product_master (product_name, qc_code, maintaining_qty, critical_qty, created_by, updated_by)
       VALUES ($1, $2, $3, $4, $5, $5)
       RETURNING *`,
      [product_name.trim(), qc_code?.trim() || null, maintaining_qty, critical_qty, req.user.id]
    );
    const product = result.rows[0];

    await logInventoryAudit(client, {
      transactionId: null, productId: product.id,
      action: 'CREATE_PRODUCT', oldData: null, newData: product, userId: req.user.id,
    });

    await client.query('COMMIT');
    res.status(201).json({ product });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('POST /inventory/products error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  } finally {
    client.release();
  }
});

// PUT /inventory/products/:id  (admin only)
router.put('/products/:id', authenticate, requireRole(['admin']), async (req, res) => {
  const { id } = req.params;
  const { product_name, qc_code, maintaining_qty, critical_qty, is_active } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Fetch current record
    const prev = await client.query('SELECT * FROM product_master WHERE id = $1', [id]);
    if (!prev.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Product not found' } });
    }
    const old = prev.rows[0];

    const result = await client.query(
      `UPDATE product_master SET
         product_name   = COALESCE($1, product_name),
         qc_code        = COALESCE($2, qc_code),
         maintaining_qty= COALESCE($3, maintaining_qty),
         critical_qty   = COALESCE($4, critical_qty),
         is_active      = COALESCE($5, is_active),
         updated_by     = $6
       WHERE id = $7
       RETURNING *`,
      [product_name?.trim(), qc_code?.trim(), maintaining_qty, critical_qty, is_active, req.user.id, id]
    );
    const updated = result.rows[0];

    await logInventoryAudit(client, {
      transactionId: null, productId: parseInt(id),
      action: 'UPDATE_PRODUCT', oldData: old, newData: updated, userId: req.user.id,
    });

    await client.query('COMMIT');
    res.json({ product: updated });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('PUT /inventory/products/:id error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  } finally {
    client.release();
  }
});

// DELETE /inventory/products/:id  – Soft delete (admin only)
router.delete('/products/:id', authenticate, requireRole(['admin']), async (req, res) => {
  const { id } = req.params;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await client.query(
      `UPDATE product_master SET is_active = FALSE, updated_by = $1 WHERE id = $2 RETURNING *`,
      [req.user.id, id]
    );
    if (!result.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Product not found' } });
    }
    await logInventoryAudit(client, {
      transactionId: null, productId: parseInt(id),
      action: 'DELETE_PRODUCT', oldData: result.rows[0], newData: null, userId: req.user.id,
    });
    await client.query('COMMIT');
    res.json({ message: 'Product deactivated', product: result.rows[0] });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('DELETE /inventory/products/:id error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  } finally {
    client.release();
  }
});

// =============================================================================
// TRANSACTION ENDPOINTS
// =============================================================================

// GET /inventory/transactions  – Transactions, filterable by date or date range
// ?date=YYYY-MM-DD  → single day
// ?from=YYYY-MM-DD&to=YYYY-MM-DD  → date range
// ?all=true  → all dates (admin only)
router.get('/transactions', authenticate, async (req, res) => {
  try {
    const isAdmin = req.user.role === 'admin';
    const { date, from, to } = req.query;

    let dateClause = '';
    let params = [];
    let paramIdx = 1;

    if (date) {
      dateClause = `AND t.transaction_date = $${paramIdx++}`;
      params.push(date);
    } else if (from && to) {
      if (!isAdmin) {
        return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'Only admins can query date ranges' } });
      }
      dateClause = `AND t.transaction_date BETWEEN $${paramIdx++} AND $${paramIdx++}`;
      params.push(from, to);
    } else {
      // Default: today only
      dateClause = `AND t.transaction_date = CURRENT_DATE`;
    }

    const result = await pool.query(
      `SELECT
          t.*,
          p.product_name,
          p.qc_code,
          p.maintaining_qty,
          p.critical_qty,
          u.username  AS created_by_name,
          ub.username AS updated_by_name,
          -- Running stock up to end of that transaction's date
          (
            SELECT COALESCE(SUM(qty_in), 0) - COALESCE(SUM(qty_out), 0)
            FROM inventory_transactions sub
            WHERE sub.product_id = t.product_id
              AND sub.transaction_date <= t.transaction_date
          ) AS running_total
       FROM inventory_transactions t
       JOIN product_master p   ON p.id  = t.product_id
       LEFT JOIN users u       ON u.id  = t.created_by
       LEFT JOIN users ub      ON ub.id = t.updated_by
       WHERE p.is_active = TRUE ${dateClause}
       ORDER BY t.transaction_date DESC, p.product_name, t.created_at`,
      params
    );
    res.json({ transactions: result.rows });
  } catch (err) {
    console.error('GET /inventory/transactions error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  }
});

// GET /inventory/dates  – Distinct dates that have transactions (for accordion building)
router.get('/dates', authenticate, async (req, res) => {
  try {
    const isAdmin = req.user.role === 'admin';
    const limit = isAdmin ? 90 : 30; // 90 days for admin, 30 for others

    const result = await pool.query(
      `SELECT DISTINCT transaction_date
       FROM inventory_transactions
       ORDER BY transaction_date DESC
       LIMIT $1`,
      [limit]
    );
    res.json({ dates: result.rows.map(r => r.transaction_date) });
  } catch (err) {
    console.error('GET /inventory/dates error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  }
});

// POST /inventory/transactions  – Create a new transaction entry
router.post('/transactions', authenticate, async (req, res) => {
  const isViewer = req.user.role === 'viewer';
  if (isViewer) {
    return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'Viewers cannot record transactions' } });
  }

  const { product_id, qty_in = 0, qty_out = 0, reference_no, remarks, transaction_date } = req.body;

  if (!product_id) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'product_id is required' } });
  }
  if (qty_in < 0 || qty_out < 0) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Quantities must be non-negative' } });
  }

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Verify product exists and is active
    const prodCheck = await client.query(
      'SELECT id FROM product_master WHERE id = $1 AND is_active = TRUE', [product_id]
    );
    if (!prodCheck.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Product not found or inactive' } });
    }

    const txDate = transaction_date || new Date().toISOString().split('T')[0];

    const result = await client.query(
      `INSERT INTO inventory_transactions
         (product_id, transaction_date, qty_in, qty_out, reference_no, remarks, created_by, updated_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $7)
       RETURNING *`,
      [product_id, txDate, qty_in, qty_out, reference_no || null, remarks || null, req.user.id]
    );
    const tx = result.rows[0];

    await logInventoryAudit(client, {
      transactionId: tx.id, productId: product_id,
      action: 'CREATE', oldData: null, newData: tx, userId: req.user.id,
    });

    await client.query('COMMIT');
    res.status(201).json({ transaction: tx });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('POST /inventory/transactions error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  } finally {
    client.release();
  }
});

// PUT /inventory/transactions/:id  – Update a transaction
// Normal users can only edit today's own entries; admin can edit any
router.put('/transactions/:id', authenticate, async (req, res) => {
  const isViewer = req.user.role === 'viewer';
  if (isViewer) {
    return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'Viewers cannot edit transactions' } });
  }

  const { id } = req.params;
  const { qty_in, qty_out, reference_no, remarks } = req.body;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const prev = await client.query('SELECT * FROM inventory_transactions WHERE id = $1', [id]);
    if (!prev.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Transaction not found' } });
    }
    const old = prev.rows[0];

    const isAdmin = req.user.role === 'admin';
    const isOwner = old.created_by === req.user.id;
    const isToday = old.transaction_date.toISOString().split('T')[0] === new Date().toISOString().split('T')[0];

    if (!isAdmin && (!isOwner || !isToday)) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'You can only edit your own transactions from today' } });
    }

    if (qty_in !== undefined && qty_in < 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'qty_in must be non-negative' } });
    }
    if (qty_out !== undefined && qty_out < 0) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'qty_out must be non-negative' } });
    }

    const result = await client.query(
      `UPDATE inventory_transactions SET
         qty_in       = COALESCE($1, qty_in),
         qty_out      = COALESCE($2, qty_out),
         reference_no = COALESCE($3, reference_no),
         remarks      = COALESCE($4, remarks),
         updated_by   = $5
       WHERE id = $6
       RETURNING *`,
      [qty_in, qty_out, reference_no, remarks, req.user.id, id]
    );
    const updated = result.rows[0];

    await logInventoryAudit(client, {
      transactionId: parseInt(id), productId: old.product_id,
      action: 'UPDATE', oldData: old, newData: updated, userId: req.user.id,
    });

    await client.query('COMMIT');
    res.json({ transaction: updated });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('PUT /inventory/transactions/:id error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  } finally {
    client.release();
  }
});

// DELETE /inventory/transactions/:id
// Normal users: only own + today; Admin: any
router.delete('/transactions/:id', authenticate, async (req, res) => {
  const isViewer = req.user.role === 'viewer';
  if (isViewer) {
    return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'Viewers cannot delete transactions' } });
  }

  const { id } = req.params;
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const prev = await client.query('SELECT * FROM inventory_transactions WHERE id = $1', [id]);
    if (!prev.rows.length) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Transaction not found' } });
    }
    const old = prev.rows[0];

    const isAdmin = req.user.role === 'admin';
    const isOwner = old.created_by === req.user.id;
    const isToday = old.transaction_date.toISOString().split('T')[0] === new Date().toISOString().split('T')[0];

    if (!isAdmin && (!isOwner || !isToday)) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: { code: 'FORBIDDEN', message: 'You can only delete your own transactions from today' } });
    }

    await client.query('DELETE FROM inventory_transactions WHERE id = $1', [id]);
    await logInventoryAudit(client, {
      transactionId: parseInt(id), productId: old.product_id,
      action: 'DELETE', oldData: old, newData: null, userId: req.user.id,
    });

    await client.query('COMMIT');
    res.json({ message: 'Transaction deleted' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('DELETE /inventory/transactions/:id error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  } finally {
    client.release();
  }
});

// GET /inventory/audit  – Audit trail for inventory (admin only)
router.get('/audit', authenticate, requireRole(['admin']), async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit) || 100, 500);
    const offset = (parseInt(req.query.page) - 1 || 0) * limit;

    const result = await pool.query(
      `SELECT a.*, u.username AS performed_by_name, p.product_name
       FROM inventory_audit_log a
       LEFT JOIN users u ON u.id = a.performed_by
       LEFT JOIN product_master p ON p.id = a.product_id
       ORDER BY a.performed_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    res.json({ audit: result.rows });
  } catch (err) {
    console.error('GET /inventory/audit error:', err);
    res.status(500).json({ error: { code: 'SERVER_ERROR', message: err.message } });
  }
});

module.exports = router;
