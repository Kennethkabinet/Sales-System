const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { requireRole } = require('../middleware/rbac');
const auditService = require('../services/auditService');

// GET /users - Get all users (Admin only)
router.get('/', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const result = await pool.query(`
      SELECT u.id, u.username, u.email, u.full_name, 
             r.name as role, d.name as department_name,
             u.is_active, u.last_login, u.created_at
      FROM users u
      LEFT JOIN roles r ON u.role_id = r.id
      LEFT JOIN departments d ON u.department_id = d.id
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
router.put('/:id/role', authenticate, requireRole('admin'), async (req, res) => {
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
router.put('/:id/department', authenticate, requireRole('admin'), async (req, res) => {
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
router.delete('/:id', authenticate, requireRole('admin'), async (req, res) => {
  try {
    const { id } = req.params;

    // Prevent self-deletion
    if (req.user.id === parseInt(id)) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Cannot delete your own account' }
      });
    }

    await pool.query('UPDATE users SET is_active = FALSE WHERE id = $1', [id]);

    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'users',
      entityId: parseInt(id)
    });

    res.json({
      success: true,
      message: 'User deactivated'
    });
  } catch (error) {
    console.error('Delete user error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to delete user' }
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
