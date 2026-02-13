const express = require('express');
const router = express.Router();
const pool = require('../db');
const { authenticate } = require('../middleware/auth');
const { checkFileAccess, requireFileAccess } = require('../middleware/rbac');
const formulaEngine = require('../services/formulaEngine');
const auditService = require('../services/auditService');

// GET /formulas - Get all formulas accessible to user (Admin and User only)
router.get('/', authenticate, requireFileAccess, async (req, res) => {
  try {
    let query = `
      SELECT f.id, f.uuid, f.name, f.description, f.expression,
             f.input_columns, f.output_column, f.is_shared,
             u.username as created_by, f.version, f.created_at
      FROM formulas f
      LEFT JOIN users u ON f.created_by = u.id
      WHERE f.is_active = TRUE
    `;
    
    const params = [];
    
    // Filter based on access
    if (req.user.role !== 'admin') {
      params.push(req.user.id, req.user.department_id);
      query += ` AND (f.is_shared = TRUE OR f.created_by = $1 OR f.department_id = $2)`;
    }
    
    query += ' ORDER BY f.name';
    
    const result = await pool.query(query, params);

    res.json({
      success: true,
      formulas: result.rows
    });

  } catch (error) {
    console.error('Get formulas error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get formulas' }
    });
  }
});

// GET /formulas/:id - Get specific formula
router.get('/:id', authenticate, requireFileAccess, async (req, res) => {
  try {
    const { id } = req.params;

    const result = await pool.query(`
      SELECT f.id, f.uuid, f.name, f.description, f.expression,
             f.input_columns, f.output_column, f.is_shared,
             u.username as created_by, f.version, f.created_at
      FROM formulas f
      LEFT JOIN users u ON f.created_by = u.id
      WHERE f.id = $1 AND f.is_active = TRUE
    `, [id]);

    if (result.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Formula not found' }
      });
    }

    res.json({
      success: true,
      formula: result.rows[0]
    });

  } catch (error) {
    console.error('Get formula error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to get formula' }
    });
  }
});

// POST /formulas - Create new formula
router.post('/', authenticate, requireFileAccess, async (req, res) => {
  try {
    const { name, description, expression, input_columns, output_column, is_shared } = req.body;

    // Validate formula expression
    const validationResult = formulaEngine.validate(expression, input_columns);
    if (!validationResult.valid) {
      return res.status(400).json({
        success: false,
        error: { code: 'FORMULA_ERROR', message: validationResult.error }
      });
    }

    // Create formula
    const result = await pool.query(`
      INSERT INTO formulas (name, description, expression, input_columns, output_column, 
                           department_id, created_by, is_shared)
      VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
      RETURNING id, uuid, name
    `, [
      name,
      description,
      expression,
      JSON.stringify(input_columns),
      output_column,
      req.user.department_id,
      req.user.id,
      is_shared || false
    ]);

    const formula = result.rows[0];

    // Create initial version
    await pool.query(`
      INSERT INTO formula_versions (formula_id, version_number, expression, input_columns, output_column, created_by)
      VALUES ($1, 1, $2, $3, $4, $5)
    `, [formula.id, expression, JSON.stringify(input_columns), output_column, req.user.id]);

    await auditService.log({
      userId: req.user.id,
      action: 'CREATE',
      entityType: 'formulas',
      entityId: formula.id,
      metadata: { name, expression }
    });

    res.status(201).json({
      success: true,
      formula: {
        id: formula.id,
        uuid: formula.uuid,
        name: formula.name
      }
    });

  } catch (error) {
    console.error('Create formula error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to create formula' }
    });
  }
});

// PUT /formulas/:id - Update formula
router.put('/:id', authenticate, requireFileAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { name, description, expression, input_columns, output_column, is_shared } = req.body;

    // Check ownership or admin
    const checkResult = await pool.query(
      'SELECT created_by, version FROM formulas WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Formula not found' }
      });
    }

    if (checkResult.rows[0].created_by !== req.user.id && req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Cannot edit this formula' }
      });
    }

    // Validate new expression
    if (expression) {
      const validationResult = formulaEngine.validate(expression, input_columns);
      if (!validationResult.valid) {
        return res.status(400).json({
          success: false,
          error: { code: 'FORMULA_ERROR', message: validationResult.error }
        });
      }
    }

    const currentVersion = checkResult.rows[0].version;
    const newVersion = currentVersion + 1;

    // Update formula
    await pool.query(`
      UPDATE formulas SET
        name = COALESCE($1, name),
        description = COALESCE($2, description),
        expression = COALESCE($3, expression),
        input_columns = COALESCE($4, input_columns),
        output_column = COALESCE($5, output_column),
        is_shared = COALESCE($6, is_shared),
        version = $7
      WHERE id = $8
    `, [name, description, expression, input_columns ? JSON.stringify(input_columns) : null, 
        output_column, is_shared, newVersion, id]);

    // Create version record
    if (expression) {
      await pool.query(`
        INSERT INTO formula_versions (formula_id, version_number, expression, input_columns, output_column, created_by)
        VALUES ($1, $2, $3, $4, $5, $6)
      `, [id, newVersion, expression, JSON.stringify(input_columns), output_column, req.user.id]);
    }

    await auditService.log({
      userId: req.user.id,
      action: 'UPDATE',
      entityType: 'formulas',
      entityId: parseInt(id),
      metadata: { name, expression }
    });

    res.json({
      success: true,
      message: 'Formula updated'
    });

  } catch (error) {
    console.error('Update formula error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to update formula' }
    });
  }
});

// POST /formulas/:id/apply - Apply formula to file
router.post('/:id/apply', authenticate, requireFileAccess, async (req, res) => {
  try {
    const { id } = req.params;
    const { file_id, column_mapping } = req.body;

    // Get formula
    const formulaResult = await pool.query(
      'SELECT expression, input_columns, output_column FROM formulas WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (formulaResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Formula not found' }
      });
    }

    const formula = formulaResult.rows[0];

    // Get file data
    const dataResult = await pool.query(
      'SELECT id, row_number, data FROM file_data WHERE file_id = $1 ORDER BY row_number',
      [file_id]
    );

    if (dataResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'File has no data' }
      });
    }

    // Apply formula to each row
    let rowsAffected = 0;
    const sampleResults = {};

    for (const row of dataResult.rows) {
      try {
        // Map columns
        const mappedValues = {};
        for (const [formulaCol, fileCol] of Object.entries(column_mapping || {})) {
          mappedValues[formulaCol] = row.data[fileCol];
        }

        // If no mapping, use direct column names
        const inputValues = Object.keys(column_mapping || {}).length > 0 
          ? mappedValues 
          : row.data;

        // Evaluate formula
        const result = formulaEngine.evaluate(formula.expression, inputValues);

        if (result.success) {
          // Update row with new calculated value
          const newData = { ...row.data, [formula.output_column]: result.value };
          await pool.query(
            'UPDATE file_data SET data = $1 WHERE id = $2',
            [JSON.stringify(newData), row.id]
          );
          rowsAffected++;

          // Store sample result
          if (Object.keys(sampleResults).length < 3) {
            sampleResults[`row_${row.row_number}`] = { [formula.output_column]: result.value };
          }
        }
      } catch (evalError) {
        console.error(`Error evaluating row ${row.row_number}:`, evalError);
      }
    }

    // Record applied formula
    await pool.query(`
      INSERT INTO applied_formulas (file_id, formula_id, column_mapping, applied_by)
      VALUES ($1, $2, $3, $4)
      ON CONFLICT (file_id, formula_id) DO UPDATE SET
        column_mapping = $3, applied_by = $4, applied_at = CURRENT_TIMESTAMP
    `, [file_id, id, JSON.stringify(column_mapping || {}), req.user.id]);

    // Add output column to file columns if not exists
    await pool.query(`
      UPDATE files 
      SET columns = (
        SELECT jsonb_agg(DISTINCT elem)
        FROM (
          SELECT jsonb_array_elements(COALESCE(columns, '[]'::jsonb)) AS elem
          UNION
          SELECT to_jsonb($1::text)
        ) sub
      )
      WHERE id = $2
    `, [formula.output_column, file_id]);

    await auditService.log({
      userId: req.user.id,
      action: 'FORMULA_APPLY',
      entityType: 'files',
      entityId: file_id,
      fileId: file_id,
      metadata: { formula_id: id, rows_affected: rowsAffected }
    });

    res.json({
      success: true,
      rows_affected: rowsAffected,
      sample_result: sampleResults
    });

  } catch (error) {
    console.error('Apply formula error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to apply formula' }
    });
  }
});

// POST /formulas/preview - Preview formula result
router.post('/preview', authenticate, requireFileAccess, async (req, res) => {
  try {
    const { expression, test_values } = req.body;

    // Validate
    const validationResult = formulaEngine.validate(expression, Object.keys(test_values));
    if (!validationResult.valid) {
      return res.status(400).json({
        success: false,
        error: { code: 'FORMULA_ERROR', message: validationResult.error }
      });
    }

    // Evaluate
    const result = formulaEngine.evaluate(expression, test_values);

    res.json({
      success: true,
      result: result.value,
      valid: result.success
    });

  } catch (error) {
    console.error('Preview formula error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to preview formula' }
    });
  }
});

// DELETE /formulas/:id - Delete formula
router.delete('/:id', authenticate, requireFileAccess, async (req, res) => {
  try {
    const { id } = req.params;

    // Check ownership or admin
    const checkResult = await pool.query(
      'SELECT created_by FROM formulas WHERE id = $1 AND is_active = TRUE',
      [id]
    );

    if (checkResult.rows.length === 0) {
      return res.status(404).json({
        success: false,
        error: { code: 'NOT_FOUND', message: 'Formula not found' }
      });
    }

    if (checkResult.rows[0].created_by !== req.user.id && req.user.role !== 'admin') {
      return res.status(403).json({
        success: false,
        error: { code: 'FORBIDDEN', message: 'Cannot delete this formula' }
      });
    }

    await pool.query('UPDATE formulas SET is_active = FALSE WHERE id = $1', [id]);

    await auditService.log({
      userId: req.user.id,
      action: 'DELETE',
      entityType: 'formulas',
      entityId: parseInt(id)
    });

    res.json({
      success: true,
      message: 'Formula deleted'
    });

  } catch (error) {
    console.error('Delete formula error:', error);
    res.status(500).json({
      success: false,
      error: { code: 'SERVER_ERROR', message: 'Failed to delete formula' }
    });
  }
});

module.exports = router;
