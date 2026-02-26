const pool = require('../db');

/**
 * Audit Service - Logs all user actions for full traceability
 */
const auditService = {
  /**
   * Log an audit entry
   * @param {Object} params - Audit parameters
   * @param {number} params.userId - User performing the action
   * @param {string} params.action - Action type (CREATE, UPDATE, DELETE, LOGIN, etc.)
   * @param {string} params.entityType - Entity type (users, files, file_data, formulas, sheet_data)
   * @param {number} params.entityId - Entity ID
   * @param {number} params.fileId - File ID (optional)
   * @param {number} params.sheetId - Sheet ID (optional)
   * @param {number} params.rowNumber - Row number (optional)
   * @param {string} params.fieldName - Field name changed (optional)
   * @param {string} params.cellReference - Cell ref e.g. "B4" (optional)
   * @param {string} params.oldValue - Old value (optional)
   * @param {string} params.newValue - New value (optional)
   * @param {string} params.role - User role at time of action (optional)
   * @param {string} params.departmentName - User department at time of action (optional)
   * @param {Object} params.metadata - Additional metadata (optional)
   * @param {string} params.ip - IP address (optional)
   * @param {string} params.userAgent - User agent (optional)
   */
  async log({
    userId,
    action,
    entityType,
    entityId,
    fileId = null,
    sheetId = null,
    rowNumber = null,
    fieldName = null,
    cellReference = null,
    oldValue = null,
    newValue = null,
    role = null,
    departmentName = null,
    metadata = {},
    ip = null,
    userAgent = null
  }) {
    try {
      await pool.query(`
        INSERT INTO audit_logs 
        (user_id, action, entity_type, entity_id, file_id, sheet_id, row_number, 
         field_name, cell_reference, old_value, new_value, role, department_name,
         metadata, ip_address, user_agent)
        VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
      `, [
        userId,
        action,
        entityType,
        entityId,
        fileId,
        sheetId,
        rowNumber,
        fieldName,
        cellReference,
        oldValue,
        newValue,
        role,
        departmentName,
        JSON.stringify(metadata),
        ip,
        userAgent
      ]);
    } catch (error) {
      console.error('Audit log error:', error);
      // Don't throw - audit failures shouldn't break main operations
    }
  },

  /**
   * Log multiple field changes at once (file-based, backward compat)
   */
  async logRowChanges(userId, fileId, rowId, rowNumber, oldData, newData) {
    const changes = [];
    
    for (const [field, newValue] of Object.entries(newData)) {
      const oldValue = oldData[field];
      if (oldValue !== newValue) {
        changes.push({
          field,
          oldValue: String(oldValue ?? ''),
          newValue: String(newValue ?? '')
        });
      }
    }
    
    for (const change of changes) {
      await this.log({
        userId,
        action: 'UPDATE',
        entityType: 'file_data',
        entityId: rowId,
        fileId,
        rowNumber,
        fieldName: change.field,
        oldValue: change.oldValue,
        newValue: change.newValue
      });
    }
    
    return changes;
  },

  /**
   * Log sheet-level cell changes with full context (role, dept, cell ref).
   * @param {Object} params
   * @param {number} params.userId
   * @param {string} params.role - User's role
   * @param {string} params.departmentName - User's department
   * @param {number} params.sheetId
   * @param {string} params.sheetName - Human-readable sheet name (stored in metadata)
   * @param {number} params.rowNumber
   * @param {string} params.columnName - Column header name
   * @param {string} params.cellReference - e.g. "B4"
   * @param {string} params.oldValue
   * @param {string} params.newValue
   */
  async logSheetCellChange({
    userId, role, departmentName,
    sheetId, sheetName,
    rowNumber, columnName, cellReference,
    oldValue, newValue
  }) {
    await this.log({
      userId,
      action:          'UPDATE',
      entityType:      'sheet_data',
      entityId:        sheetId,
      sheetId,
      rowNumber,
      fieldName:       columnName,
      cellReference,
      oldValue:        String(oldValue ?? ''),
      newValue:        String(newValue ?? ''),
      role,
      departmentName,
      metadata:        { sheet_name: sheetName, column_name: columnName }
    });
  },

  /**
   * Get audit trail for a specific entity
   */
  async getHistory(entityType, entityId, limit = 100) {
    const result = await pool.query(`
      SELECT al.*, u.username
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      WHERE al.entity_type = $1 AND al.entity_id = $2
      ORDER BY al.created_at DESC
      LIMIT $3
    `, [entityType, entityId, limit]);
    
    return result.rows;
  },

  /**
   * Get recent activity for dashboard
   */
  async getRecentActivity(limit = 10) {
    const result = await pool.query(`
      SELECT al.action, al.entity_type, u.username, f.name as file_name, al.created_at
      FROM audit_logs al
      LEFT JOIN users u ON al.user_id = u.id
      LEFT JOIN files f ON al.file_id = f.id
      ORDER BY al.created_at DESC
      LIMIT $1
    `, [limit]);
    
    return result.rows;
  }
};

module.exports = auditService;
