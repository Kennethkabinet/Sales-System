// Role-Based Access Control Middleware

// Check if user has required role
const requireRole = (...allowedRoles) => {
  return (req, res, next) => {
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
      });
    }
    
    if (!allowedRoles.includes(req.user.role)) {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Insufficient permissions' }
      });
    }
    
    next();
  };
};

// Admin-only access (dashboard, user management, audit)
const requireAdminAccess = (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
    });
  }
  
  if (req.user.role !== 'admin') {
    return res.status(403).json({
      success: false,
      error: { code: 'FORBIDDEN', message: 'Admin access required' }
    });
  }
  
  next();
};

// Sheet access (admin, editor, viewer, user)
const requireSheetAccess = (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
    });
  }
  
  if (!['admin', 'editor', 'viewer', 'user'].includes(req.user.role)) {
    return res.status(403).json({
      success: false,
      error: { code: 'FORBIDDEN', message: 'Sheet access denied' }
    });
  }
  
  next();
};

// Sheet edit access (admin, editor, user - NOT viewer)
const requireSheetEditAccess = (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
    });
  }
  
  if (!['admin', 'editor', 'user'].includes(req.user.role)) {
    return res.status(403).json({
      success: false,
      error: { code: 'FORBIDDEN', message: 'Permission to edit denied. Viewer role is read-only.' }
    });
  }
  
  next();
};

// File management access (admin, editor, user - NOT viewer)
const requireFileAccess = (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
    });
  }
  
  if (!['admin', 'editor', 'user'].includes(req.user.role)) {
    return res.status(403).json({
      success: false,
      error: { code: 'FORBIDDEN', message: 'File access denied. Not available for viewers.' }
    });
  }
  
  next();
};

// Check department access
const requireDepartmentAccess = async (req, res, next) => {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
    });
  }
  
  // Admins can access all departments
  if (req.user.role === 'admin') {
    return next();
  }
  
  const requestedDepartmentId = req.params.departmentId || req.body.department_id || req.query.department_id;
  
  // If no specific department requested, allow
  if (!requestedDepartmentId) {
    return next();
  }
  
  // Check if user belongs to the requested department
  if (parseInt(requestedDepartmentId) !== req.user.department_id) {
    return res.status(403).json({
      success: false,
      error: { code: 'FORBIDDEN', message: 'Access denied to this department' }
    });
  }
  
  next();
};

// Check file access permissions
const checkFileAccess = (requiredLevel = 'read') => {
  return async (req, res, next) => {
    const pool = require('../db');
    
    if (!req.user) {
      return res.status(401).json({
        success: false,
        error: { code: 'AUTH_REQUIRED', message: 'Authentication required' }
      });
    }
    
    // Admins have full access
    if (req.user.role === 'admin') {
      return next();
    }
    
    const fileId = req.params.id || req.params.fileId || req.body.file_id;
    
    if (!fileId) {
      return next();
    }
    
    try {
      // Get file info
      const fileResult = await pool.query(
        'SELECT department_id, created_by FROM files WHERE id = $1',
        [fileId]
      );
      
      if (fileResult.rows.length === 0) {
        return res.status(404).json({
          success: false,
          error: { code: 'NOT_FOUND', message: 'File not found' }
        });
      }
      
      const file = fileResult.rows[0];
      
      // Check if user is the creator
      if (file.created_by === req.user.id) {
        return next();
      }
      
      // Check department access
      if (file.department_id === req.user.department_id) {
        // Check specific permissions for non-owners
        const permResult = await pool.query(
          'SELECT permission_level FROM file_permissions WHERE file_id = $1 AND user_id = $2',
          [fileId, req.user.id]
        );
        
        if (permResult.rows.length > 0) {
          const perm = permResult.rows[0].permission_level;
          const levels = { 'read': 1, 'write': 2, 'admin': 3 };
          
          if (levels[perm] >= levels[requiredLevel]) {
            return next();
          }
        }
        
        // Default department access
        if (requiredLevel === 'read') {
          return next();
        }
        
        // Viewers can only read
        if (req.user.role === 'viewer' && requiredLevel !== 'read') {
          return res.status(403).json({
            success: false,
            error: { code: 'FORBIDDEN', message: 'Viewer role cannot modify files' }
          });
        }
        
        // Regular users and editors can write to department files
        if ((req.user.role === 'user' || req.user.role === 'editor') && requiredLevel === 'write') {
          return next();
        }
      }
      
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Access denied to this file' }
      });
      
    } catch (error) {
      console.error('File access check error:', error);
      return res.status(500).json({
        success: false,
        error: { code: 'SERVER_ERROR', message: 'Error checking file access' }
      });
    }
  };
};

module.exports = { 
  requireRole, 
  requireAdminAccess,
  requireSheetAccess,
  requireSheetEditAccess,
  requireFileAccess,
  requireDepartmentAccess, 
  checkFileAccess 
};
