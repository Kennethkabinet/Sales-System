const jwt = require('jsonwebtoken');
const pool = require('../db');

const JWT_SECRET = process.env.JWT_SECRET || 'your-secret-key-change-in-production';

// Authentication middleware
const authenticate = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({
        success: false,
        error: { code: 'AUTH_REQUIRED', message: 'Authentication token required' }
      });
    }
    
    const token = authHeader.split(' ')[1];
    
    try {
      const decoded = jwt.verify(token, JWT_SECRET);
      
      // Get user from database
      const result = await pool.query(`
        SELECT u.id, u.username, u.email, u.full_name, u.department_id, u.is_active,
               r.name as role, d.name as department_name
        FROM users u
        LEFT JOIN roles r ON u.role_id = r.id
        LEFT JOIN departments d ON u.department_id = d.id
        WHERE u.id = $1
      `, [decoded.userId]);
      
      if (result.rows.length === 0) {
        return res.status(401).json({
          success: false,
          error: { code: 'AUTH_INVALID', message: 'User not found or inactive' }
        });
      }

      if (!result.rows[0].is_active) {
        return res.status(403).json({
          success: false,
          error: { code: 'ACCOUNT_SUSPENDED', message: 'Account is suspended' }
        });
      }
      
      req.user = result.rows[0];
      next();
    } catch (jwtError) {
      return res.status(401).json({
        success: false,
        error: { code: 'AUTH_INVALID', message: 'Invalid or expired token' }
      });
    }
  } catch (error) {
    console.error('Auth middleware error:', error);
    return res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Authentication error' }
    });
  }
};

// Generate JWT token
const generateToken = (userId, role) => {
  return jwt.sign(
    { userId, role },
    JWT_SECRET,
    { expiresIn: '24h' }
  );
};

module.exports = { authenticate, generateToken, JWT_SECRET };
