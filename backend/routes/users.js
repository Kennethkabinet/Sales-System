const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const { body, validationResult } = require('express-validator');
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { requireAdminAccess } = require('../middleware/rbac');
const auditService = require('../services/auditService');

// Validation rules for user creation
const createUserValidation = [
  body('username').trim().isLength({ min: 3, max: 50 }).withMessage('Username must be 3-50 characters'),
  body('email').isEmail().normalizeEmail().withMessage('Valid email required'),
  body('password').isLength({ min: 6 }).withMessage('Password must be at least 6 characters'),
  body('full_name').trim().notEmpty().withMessage('Full name is required'),
  body('role').isIn(['viewer', 'editor']).withMessage('Role must be viewer or editor'),
  body('department_id').optional().isInt()
];

// POST /users - Create new user (Admin only)
router.post('/', authenticate, requireAdminAccess, createUserValidation, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Invalid input', details: errors.array() }
      });
    }

    const { username, email, password, full_name, role, department_id } = req.body;

    // Check if user exists
    const existingUser = await pool.query(
      'SELECT id FROM users WHERE username = $1 OR email = $2',
      [username, email]
    );

    if (existingUser.rows.length > 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Username or email already exists' }
      });
    }

    // Get role id
    const roleResult = await pool.query('SELECT id FROM roles WHERE name = $1', [role]);
    if (roleResult.rows.length === 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Invalid role' }
      });
    }

    const roleId = roleResult.rows[0].id;

    // Hash password
    const passwordHash = await bcrypt.hash(password, 10);

    // Insert user
    const result = await pool.query(`
      INSERT INTO users (username, email, password_hash, full_name, department_id, role_id, created_by)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING id, username, email, full_name, is_active, created_at
    `, [username, email, passwordHash, full_name, department_id || null, roleId, req.user.id]);

    const user = result.rows[0];

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'CREATE',
      entityType: 'users',
      entityId: user.id,
      metadata: { username: user.username, role, created_by: req.user.username }
    });

    res.status(201).json({
      success: true,
      message: 'User created successfully',
      user: {
        ...user,
        role
      }
    });

  } catch (error) {
    console.error('Create user error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to create user' }
    });
  }
});

// GET /users - Get all users (Admin only)
router.get('/', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT u.id, u.username, u.email, u.full_name, 
             r.name as role, d.name as department_name,
             u.is_active, u.last_login, u.created_at, u.deactivated_at,
             creator.username as created_by_name
      FROM users u
      LEFT JOIN roles r ON u.role_id = r.id
      LEFT JOIN departments d ON u.department_id = d.id
      LEFT JOIN users creator ON u.created_by = creator.id
      ORDER BY u.created_at DESC
    `);

    res.json({
      success: true,
      users: result.rows
    });
  } catch (error) {
    console.error('Get users error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get users' }
    });
  }
});

// PUT /users/:id - Update user (Admin only)
router.put('/:id', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { username, email, full_name, role, department_id, password } = req.body;

    // Prevent updating own role if admin
    if (parseInt(id) === req.user.id && role && role !== 'admin') {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Cannot change your own role' }
      });
    }

    // Check if username or email already used by another user
    if (username || email) {
      const existingUser = await pool.query(
        'SELECT id FROM users WHERE (username = $1 OR email = $2) AND id != $3',
        [username || '', email || '', id]
      );

      if (existingUser.rows.length > 0) {
        return res.status(400).json({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'Username or email already exists' }
        });
      }
    }

    // Get current user data for audit
    const currentUser = await pool.query(
      'SELECT username, email, full_name, role_id, department_id FROM users WHERE id = $1',
      [id]
    );

    if (currentUser.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'User not found' }
      });
    }

    const updates = [];
    const values = [];
    let paramCount = 1;

    if (username) {
      updates.push(`username = $${paramCount++}`);
      values.push(username);
    }
    if (email) {
      updates.push(`email = $${paramCount++}`);
      values.push(email);
    }
    if (full_name) {
      updates.push(`full_name = $${paramCount++}`);
      values.push(full_name);
    }
    if (department_id !== undefined) {
      updates.push(`department_id = $${paramCount++}`);
      values.push(department_id);
    }
    if (password) {
      const passwordHash = await bcrypt.hash(password, 10);
      updates.push(`password_hash = $${paramCount++}`);
      values.push(passwordHash);
    }
    if (role) {
      const roleResult = await pool.query('SELECT id FROM roles WHERE name = $1', [role]);
      if (roleResult.rows.length === 0) {
        return res.status(400).json({
          success: false,
          error: { code: 'VALIDATION_ERROR', message: 'Invalid role' }
        });
      }
      updates.push(`role_id = $${paramCount++}`);
      values.push(roleResult.rows[0].id);
    }

    if (updates.length === 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'No fields to update' }
      });
    }

    values.push(id);
    const query = `UPDATE users SET ${updates.join(', ')} WHERE id = $${paramCount}`;
    await pool.query(query, values);

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'UPDATE',
      entityType: 'users',
      entityId: parseInt(id),
      metadata: { updated_by: req.user.username, fields: Object.keys(req.body) }
    });

    res.json({
      success: true,
      message: 'User updated successfully'
    });

  } catch (error) {
    console.error('Update user error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update user' }
    });
  }
});

// GET /users/:id - Get specific user
router.get('/:id', authenticate, async (req, res) => {
  try {
    const { id } = req.params;
    
    // Non-admins can only view their own profile
    if (req.user.role !== 'admin' && req.user.id !== parseInt(id)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Access denied' }
      });
    }

    const result = await pool.query(`
      SELECT u.id, u.username, u.email, u.full_name, 
             r.name as role, d.name as department_name,
             u.is_active, u.last_login, u.created_at
      FROM users u
      LEFT JOIN roles r ON u.role_id = r.id
      LEFT JOIN departments d ON u.department_id = d.id
      WHERE u.id = $1
    `, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'User not found' }
      });
    }

    res.json({
      success: true,
      user: result.rows[0]
    });
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get user' }
    });
  }
});

// PUT /users/:id/role - Update user role (Admin only)
router.put('/:id/role', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { role } = req.body;

    // Get role id
    const roleResult = await pool.query('SELECT id FROM roles WHERE name = $1', [role]);
    if (roleResult.rows.length === 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Invalid role' }
      });
    }

    const roleId = roleResult.rows[0].id;

    // Get old role for audit
    const oldRoleResult = await pool.query(`
      SELECT r.name as role FROM users u
      LEFT JOIN roles r ON u.role_id = r.id
      WHERE u.id = $1
    `, [id]);

    if (oldRoleResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'User not found' }
      });
    }

    const oldRole = oldRoleResult.rows[0].role;

    // Update role
    await pool.query('UPDATE users SET role_id = $1 WHERE id = $2', [roleId, id]);

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'UPDATE',
      entityType: 'users',
      entityId: parseInt(id),
      fieldName: 'role',
      oldValue: oldRole,
      newValue: role
    });

    res.json({
      success: true,
      message: 'User role updated'
    });
  } catch (error) {
    console.error('Update role error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update role' }
    });
  }
});

// PUT /users/:id/department - Update user department (Admin only)
router.put('/:id/department', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { department_id } = req.body;

    // Verify department exists
    const deptResult = await pool.query('SELECT id, name FROM departments WHERE id = $1', [department_id]);
    if (deptResult.rows.length === 0) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Invalid department' }
      });
    }

    // Get old department for audit
    const oldDeptResult = await pool.query(`
      SELECT d.name as department FROM users u
      LEFT JOIN departments d ON u.department_id = d.id
      WHERE u.id = $1
    `, [id]);

    const oldDept = oldDeptResult.rows[0]?.department || 'None';

    // Update department
    await pool.query('UPDATE users SET department_id = $1 WHERE id = $2', [department_id, id]);

    await auditService.log({
      userId: req.user.id,
      action: 'UPDATE',
      entityType: 'users',
      entityId: parseInt(id),
      fieldName: 'department',
      oldValue: oldDept,
      newValue: deptResult.rows[0].name
    });

    res.json({
      success: true,
      message: 'User department updated'
    });
  } catch (error) {
    console.error('Update department error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update department' }
    });
  }
});

// DELETE /users/:id - Deactivate user (Admin only)
router.delete('/:id', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Prevent self-deletion
    if (req.user.id === parseInt(id)) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Cannot deactivate your own account' }
      });
    }

    // Check if user exists
    const userCheck = await pool.query('SELECT id, username FROM users WHERE id = $1', [id]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'User not found' }
      });
    }

    await pool.query(
      'UPDATE users SET is_active = FALSE, deactivated_at = CURRENT_TIMESTAMP, deactivated_by = $1 WHERE id = $2',
      [req.user.id, id]
    );

    await auditService.log({
      userId: req.user.id,
      action: 'DEACTIVATE',
      entityType: 'users',
      entityId: parseInt(id),
      metadata: { deactivated_by: req.user.username }
    });

    res.json({
      success: true,
      message: 'User deactivated successfully'
    });
  } catch (error) {
    console.error('Deactivate user error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to deactivate user' }
    });
  }
});

// PUT /users/:id/reactivate - Reactivate user (Admin only)
router.put('/:id/reactivate', authenticate, requireAdminAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Check if user exists
    const userCheck = await pool.query('SELECT id, username, is_active FROM users WHERE id = $1', [id]);
    if (userCheck.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'User not found' }
      });
    }

    if (userCheck.rows[0].is_active) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'User is already active' }
      });
    }

    await pool.query(
      'UPDATE users SET is_active = TRUE, deactivated_at = NULL, deactivated_by = NULL WHERE id = $1',
      [id]
    );

    await auditService.log({
      userId: req.user.id,
      action: 'REACTIVATE',
      entityType: 'users',
      entityId: parseInt(id),
      metadata: { reactivated_by: req.user.username }
    });

    res.json({
      success: true,
      message: 'User reactivated successfully'
    });
  } catch (error) {
    console.error('Reactivate user error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to reactivate user' }
    });
  }
});

// GET /users/departments - Get all departments
router.get('/meta/departments', authenticate, async (req, res) => {
  try {
    const result = await pool.query('SELECT id, name, description FROM departments ORDER BY name');
    res.json({
      success: true,
      departments: result.rows
    });
  } catch (error) {
    console.error('Get departments error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get departments' }
    });
  }
});

// GET /users/roles - Get all roles
router.get('/meta/roles', authenticate, async (req, res) => {
  try {
    const result = await pool.query('SELECT id, name, description FROM roles ORDER BY id');
    res.json({
      success: true,
      roles: result.rows
    });
  } catch (error) {
    console.error('Get roles error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get roles' }
    });
  }
});

module.exports = router;
