const express = require('express');
const router = express.Router();
const multer = require('multer');
const path = require('path');
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { checkFileAccess } = require('../middleware/rbac');
const excelService = require('../services/excelService');
const auditService = require('../services/auditService');

// Configure multer for file uploads
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, path.join(__dirname, '../uploads'));
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + '-' + file.originalname);
  }
});

const upload = multer({
  storage,
  fileFilter: (req, file, cb) => {
    const ext = path.extname(file.originalname).toLowerCase();
    if (ext !== '.xlsx' && ext !== '.xls') {
      return cb(new Error('Only Excel files are allowed'));
    }
    cb(null, true);
  },
  limits: { fileSize: 10 * 1024 * 1024 } // 10MB limit
});

// GET /files - Get files accessible to user
router.get('/', authenticate, async (req, res) => {
  try {
    const department_id = req.query.department_id ? parseInt(req.query.department_id) : null;
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const offset = (page - 1) * limit;
    
    console.log('GET /files - user:', req.user.id, 'role:', req.user.role, 'dept:', req.user.department_id);
    
    // Build query based on role
    let query;
    let countQuery;
    let params;
    let countParams;
    
    if (req.user.role === 'admin') {
      // Admin sees all files (optionally filtered by department)
      if (department_id) {
        query = `
          SELECT f.id, f.uuid, f.name, f.original_filename, f.file_type,
                 f.department_id, d.name as department_name,
                 u.username as created_by, f.current_version,
                 f.columns, f.created_at, f.updated_at,
                 (SELECT COUNT(*) FROM file_data fd WHERE fd.file_id = f.id) as row_count
          FROM files f
          LEFT JOIN departments d ON f.department_id = d.id
          LEFT JOIN users u ON f.created_by = u.id
          WHERE f.is_active = TRUE AND f.department_id = $1
          ORDER BY f.updated_at DESC
          LIMIT $2 OFFSET $3
        `;
        countQuery = `SELECT COUNT(*) as total FROM files f WHERE f.is_active = TRUE AND f.department_id = $1`;
        params = [department_id, limit, offset];
        countParams = [department_id];
      } else {
        query = `
          SELECT f.id, f.uuid, f.name, f.original_filename, f.file_type,
                 f.department_id, d.name as department_name,
                 u.username as created_by, f.current_version,
                 f.columns, f.created_at, f.updated_at,
                 (SELECT COUNT(*) FROM file_data fd WHERE fd.file_id = f.id) as row_count
          FROM files f
          LEFT JOIN departments d ON f.department_id = d.id
          LEFT JOIN users u ON f.created_by = u.id
          WHERE f.is_active = TRUE
          ORDER BY f.updated_at DESC
          LIMIT $1 OFFSET $2
        `;
        countQuery = `SELECT COUNT(*) as total FROM files f WHERE f.is_active = TRUE`;
        params = [limit, offset];
        countParams = [];
      }
    } else {
      // Non-admin sees files in their department or created by them
      query = `
        SELECT f.id, f.uuid, f.name, f.original_filename, f.file_type,
               f.department_id, d.name as department_name,
               u.username as created_by, f.current_version,
               f.columns, f.created_at, f.updated_at,
               (SELECT COUNT(*) FROM file_data fd WHERE fd.file_id = f.id) as row_count
        FROM files f
        LEFT JOIN departments d ON f.department_id = d.id
        LEFT JOIN users u ON f.created_by = u.id
        WHERE f.is_active = TRUE AND (f.department_id = $1 OR f.created_by = $2)
        ORDER BY f.updated_at DESC
        LIMIT $3 OFFSET $4
      `;
      countQuery = `SELECT COUNT(*) as total FROM files f WHERE f.is_active = TRUE AND (f.department_id = $1 OR f.created_by = $2)`;
      params = [req.user.department_id, req.user.id, limit, offset];
      countParams = [req.user.department_id, req.user.id];
    }
    
    console.log('Files query params:', params);
    
    const countResult = await pool.query(countQuery, countParams);
    const total = parseInt(countResult.rows[0]?.total || 0);
    
    const result = await pool.query(query, params);
    
    console.log('Files found:', result.rows.length);
    
    res.json({
      success: true,
      files: result.rows,
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total,
        pages: Math.ceil(total / limit)
      }
    });
  } catch (error) {
    console.error('Get files error:', error.message);
    console.error('Stack:', error.stack);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get files' }
    });
  }
});

// POST /files/upload - Upload Excel file
router.post('/upload', authenticate, upload.single('file'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({
        success: false,
        error: { code: 'FILE_ERROR', message: 'No file uploaded' }
      });
    }

    const { name, department_id, column_mapping } = req.body;
    const columnMappingObj = column_mapping ? JSON.parse(column_mapping) : {};

    // Parse Excel file
    const parseResult = await excelService.parseExcel(req.file.path, columnMappingObj);
    
    if (!parseResult.success) {
      return res.status(400).json({
        success: false,
        error: { code: 'FILE_ERROR', message: parseResult.error }
      });
    }

    // Create file record
    const fileResult = await pool.query(`
      INSERT INTO files (name, original_filename, file_path, department_id, created_by, column_mapping, columns)
      VALUES ($1, $2, $3, $4, $5, $6, $7)
      RETURNING id, uuid, name
    `, [
      name || req.file.originalname,
      req.file.originalname,
      req.file.path,
      department_id || req.user.department_id,
      req.user.id,
      JSON.stringify(columnMappingObj),
      JSON.stringify(parseResult.columns)
    ]);

    const file = fileResult.rows[0];

    // Insert file data
    for (let i = 0; i < parseResult.data.length; i++) {
      await pool.query(`
        INSERT INTO file_data (file_id, row_number, data)
        VALUES ($1, $2, $3)
      `, [file.id, i + 1, JSON.stringify(parseResult.data[i])]);
    }

    // Create initial version
    await pool.query(`
      INSERT INTO file_versions (file_id, version_number, file_path, created_by, changes_summary)
      VALUES ($1, 1, $2, $3, 'Initial upload')
    `, [file.id, req.file.path, req.user.id]);

    // Audit log
    await auditService.log({
      userId: req.user.id,
      action: 'CREATE',
      entityType: 'files',
      entityId: file.id,
      fileId: file.id,
      metadata: { filename: req.file.originalname, rows: parseResult.data.length }
    });

    res.status(201).json({
      success: true,
      file: {
        id: file.id,
        uuid: file.uuid,
        name: file.name,
        rows_imported: parseResult.data.length,
        columns: parseResult.columns
      }
    });

  } catch (error) {
    console.error('Upload error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to upload file' }
    });
  }
});

// GET /files/:id/data - Get file data for table view
router.get('/:id/data', authenticate, checkFileAccess('read'), async (req, res) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 50 } = req.query;
    const offset = (page - 1) * limit;

    // Get file info
    const fileResult = await pool.query(`
      SELECT id, name, columns FROM files WHERE id = $1 AND is_active = TRUE
    `, [id]);

    if (fileResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'File not found' }
      });
    }

    const file = fileResult.rows[0];

    // Get data with row locks
    const dataResult = await pool.query(`
      SELECT fd.id as row_id, fd.row_number, fd.data as values,
             u.username as locked_by
      FROM file_data fd
      LEFT JOIN row_locks rl ON fd.id = rl.row_id AND rl.expires_at > CURRENT_TIMESTAMP
      LEFT JOIN users u ON rl.locked_by = u.id
      WHERE fd.file_id = $1
      ORDER BY fd.row_number
      LIMIT $2 OFFSET $3
    `, [id, limit, offset]);

    // Get total count
    const countResult = await pool.query(
      'SELECT COUNT(*) as total FROM file_data WHERE file_id = $1',
      [id]
    );

    res.json({
      success: true,
      file: {
        id: file.id,
        name: file.name,
        columns: file.columns || []
      },
      data: dataResult.rows.map(row => ({
        row_id: row.row_id,
        row_number: row.row_number,
        values: row.values,
        locked_by: row.locked_by
      })),
      pagination: {
        page: parseInt(page),
        limit: parseInt(limit),
        total: parseInt(countResult.rows[0].total)
      }
    });

  } catch (error) {
    console.error('Get file data error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get file data' }
    });
  }
});

// PUT /files/:id/data/:rowId - Update row data
router.put('/:id/data/:rowId', authenticate, checkFileAccess('write'), async (req, res) => {
  try {
    const { id, rowId } = req.params;
    const { values } = req.body;

    // Check if row exists and get current data
    const rowResult = await pool.query(`
      SELECT fd.id, fd.data, fd.row_number, rl.locked_by
      FROM file_data fd
      LEFT JOIN row_locks rl ON fd.id = rl.row_id AND rl.expires_at > CURRENT_TIMESTAMP
      WHERE fd.id = $1 AND fd.file_id = $2
    `, [rowId, id]);

    if (rowResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Row not found' }
      });
    }

    const row = rowResult.rows[0];

    // Check lock
    if (row.locked_by && row.locked_by !== req.user.id) {
      const lockUser = await pool.query('SELECT username FROM users WHERE id = $1', [row.locked_by]);
      return res.status(409).json({
        success: false,
        error: { code: 'ROW_LOCKED', message: `Row is being edited by ${lockUser.rows[0]?.username || 'another user'}` }
      });
    }

    const oldData = row.data;
    const newData = { ...oldData, ...values };

    // Update row
    await pool.query(
      'UPDATE file_data SET data = $1 WHERE id = $2',
      [JSON.stringify(newData), rowId]
    );

    // Log each field change
    const changes = [];
    for (const [field, newValue] of Object.entries(values)) {
      const oldValue = oldData[field];
      if (oldValue !== newValue) {
        changes.push({ field, old_value: String(oldValue), new_value: String(newValue) });
        
        await auditService.log({
          userId: req.user.id,
          action: 'UPDATE',
          entityType: 'file_data',
          entityId: parseInt(rowId),
          fileId: parseInt(id),
          rowNumber: row.row_number,
          fieldName: field,
          oldValue: String(oldValue),
          newValue: String(newValue)
        });
      }
    }

    // Update file version
    await pool.query(
      'UPDATE files SET current_version = current_version + 1, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
      [id]
    );

    res.json({
      success: true,
      row: {
        row_id: parseInt(rowId),
        values: newData
      },
      audit: {
        changes
      }
    });

  } catch (error) {
    console.error('Update row error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update row' }
    });
  }
});

// POST /files/:id/rows - Add new row
router.post('/:id/rows', authenticate, checkFileAccess('write'), async (req, res) => {
  try {
    const { id } = req.params;
    const { values } = req.body;

    // Get max row number
    const maxResult = await pool.query(
      'SELECT COALESCE(MAX(row_number), 0) as max_row FROM file_data WHERE file_id = $1',
      [id]
    );
    const newRowNumber = maxResult.rows[0].max_row + 1;

    // Insert new row
    const result = await pool.query(`
      INSERT INTO file_data (file_id, row_number, data)
      VALUES ($1, $2, $3)
      RETURNING id, row_number
    `, [id, newRowNumber, JSON.stringify(values)]);

    await auditService.log({
      userId: req.user.id,
      action: 'CREATE',
      entityType: 'file_data',
      entityId: result.rows[0].id,
      fileId: parseInt(id),
      rowNumber: newRowNumber,
      metadata: values
    });

    res.status(201).json({
      success: true,
      row: {
        row_id: result.rows[0].id,
        row_number: newRowNumber,
        values
      }
    });

  } catch (error) {
    console.error('Add row error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to add row' }
    });
  }
});

// DELETE /files/:id/data/:rowId - Delete row
router.delete('/:id/data/:rowId', authenticate, checkFileAccess('write'), async (req, res) => {
  try {
    const { id, rowId } = req.params;

    // Viewers and regular users in some cases might not be able to delete
    if (req.user.role === 'viewer') {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Viewers cannot delete rows' }
      });
    }

    const result = await pool.query(
      'DELETE FROM file_data WHERE id = $1 AND file_id = $2 RETURNING row_number',
      [rowId, id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Row not found' }
      });
    }

    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'file_data',
      entityId: parseInt(rowId),
      fileId: parseInt(id),
      rowNumber: result.rows[0].row_number
    });

    res.json({
      success: true,
      message: 'Row deleted'
    });

  } catch (error) {
    console.error('Delete row error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to delete row' }
    });
  }
});

// GET /files/:id/versions - Get file version history
router.get('/:id/versions', authenticate, checkFileAccess('read'), async (req, res) => {
  try {
    const { id } = req.params;

    const result = await pool.query(`
      SELECT fv.version_number as version, fv.created_at, 
             u.username as created_by, fv.changes_summary
      FROM file_versions fv
      LEFT JOIN users u ON fv.created_by = u.id
      WHERE fv.file_id = $1
      ORDER BY fv.version_number DESC
    `, [id]);

    res.json({
      success: true,
      versions: result.rows
    });

  } catch (error) {
    console.error('Get versions error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get versions' }
    });
  }
});

// POST /files/:id/export - Export file as Excel
router.post('/:id/export', authenticate, checkFileAccess('read'), async (req, res) => {
  try {
    const { id } = req.params;

    // Get file and data
    const fileResult = await pool.query('SELECT name, columns FROM files WHERE id = $1', [id]);
    if (fileResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'File not found' }
      });
    }

    const dataResult = await pool.query(
      'SELECT data FROM file_data WHERE file_id = $1 ORDER BY row_number',
      [id]
    );

    const exportPath = await excelService.exportToExcel(
      fileResult.rows[0].name,
      fileResult.rows[0].columns || [],
      dataResult.rows.map(r => r.data)
    );

    res.download(exportPath, fileResult.rows[0].name + '.xlsx');

  } catch (error) {
    console.error('Export error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to export file' }
    });
  }
});

// DELETE /files/:id - Delete file (soft delete)
router.delete('/:id', authenticate, checkFileAccess('admin'), async (req, res) => {
  try {
    const { id } = req.params;

    await pool.query('UPDATE files SET is_active = FALSE WHERE id = $1', [id]);

    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'files',
      entityId: parseInt(id),
      fileId: parseInt(id)
    });

    res.json({
      success: true,
      message: 'File deleted'
    });

  } catch (error) {
    console.error('Delete file error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to delete file' }
    });
  }
});

module.exports = router;
