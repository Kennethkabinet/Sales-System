const express = require('express');
const router = express.Router();
const bcrypt = require('bcrypt');
const { body, validationResult } = require('express-validator');
const pool = require('../db');
const { authenticate, generateToken } = require('../middleware/auth');
const auditService = require('../services/auditService');

// Validation rules
const loginValidation = [
  body('username').trim().notEmpty().withMessage('Username required'),
  body('password').notEmpty().withMessage('Password required')
];

// POST /auth/login
router.post('/login', loginValidation, async (req, res) => {
  try {
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        error: { code: 'VALIDATION_ERROR', message: 'Invalid input', details: errors.array() }
      });
    }

    const { username, password } = req.body;

    // Get user with role and department
    const result = await pool.query(`
      SELECT u.id, u.username, u.email, u.password_hash, u.full_name, u.department_id,
             r.name as role, d.name as department_name
      FROM users u
      LEFT JOIN roles r ON u.role_id = r.id
      LEFT JOIN departments d ON u.department_id = d.id
      WHERE u.username = $1 AND u.is_active = TRUE
    `, [username]);

    if (result.rows.length === 0) {
      return res.status(401).json({
        success: false,
        error: { code: 'AUTH_INVALID', message: 'Invalid username or password' }
      });
    }

    const user = result.rows[0];

    // Verify password
    const validPassword = await bcrypt.compare(password, user.password_hash);
    if (!validPassword) {
      return res.status(401).json({
        success: false,
        error: { code: 'AUTH_INVALID', message: 'Invalid username or password' }
      });
    }

    // Generate token
    const token = generateToken(user.id, user.role);

    // Update last login
    await pool.query('UPDATE users SET last_login = CURRENT_TIMESTAMP WHERE id = $1', [user.id]);

    // Log login
    await auditService.log({
      userId: user.id,
      action: 'LOGIN',
      entityType: 'users',
      entityId: user.id,
      ip: req.ip,
      userAgent: req.get('User-Agent')
    });

    // Role-based module assignment
    let moduleAccess = {};
    let redirectPath = '/';
    
    switch (user.role) {
      case 'admin':
        moduleAccess = {
          dashboard: true,
          sheets: true,
          settings: true,
          userManagement: true,
          audit: true,
          files: true,
          formulas: true
        };
        redirectPath = '/dashboard';
        break;
      case 'editor':
        moduleAccess = {
          dashboard: false,
          sheets: true,
          settings: true,
          userManagement: false,
          audit: false,
          files: false,
          formulas: false
        };
        redirectPath = '/sheets';
        break;
      case 'viewer':
        moduleAccess = {
          dashboard: false,
          sheets: true,
          settings: true,
          userManagement: false,
          audit: false,
          files: false,
          formulas: false
        };
        redirectPath = '/sheets';
        break;
      case 'user':
        moduleAccess = {
          dashboard: false,
          sheets: true,
          settings: true,
          userManagement: false,
          audit: false,
          files: true,
          formulas: true
        };
        redirectPath = '/sheets';
        break;
      default:
        moduleAccess = {
          dashboard: false,
          sheets: false,
          settings: false,
          userManagement: false,
          audit: false,
          files: false,
          formulas: false
        };
        redirectPath = '/login';
    }

    res.json({
      success: true,
      token,
      user: {
        id: user.id,
        username: user.username,
        email: user.email,
        full_name: user.full_name,
        role: user.role,
        department_id: user.department_id,
        department_name: user.department_name
      },
      moduleAccess,
      redirectPath
    });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Login failed' }
    });
  }
});

// GET /auth/me
router.get('/me', authenticate, async (req, res) => {
  res.json({
    success: true,
    user: req.user
  });
});

// POST /auth/logout
router.post('/logout', authenticate, async (req, res) => {
  // In a full implementation, you would invalidate the token here
  await auditService.log({
    userId: req.user.id,
    action: 'LOGOUT',
    entityType: 'users',
    entityId: req.user.id
  });

  res.json({
    success: true,
    message: 'Logged out successfully'
  });
});

module.exports = router;
