const math = require('mathjs');

/**
 * Formula Engine - Evaluates custom user-defined formulas
 * Supports basic arithmetic, mathematical functions, and conditional logic
 */
const formulaEngine = {
  /**
   * Validate a formula expression
   * @param {string} expression - Formula expression
   * @param {Array} inputColumns - Expected input column names
   * @returns {Object} Validation result
   */
  validate(expression, inputColumns = []) {
    try {
      if (!expression || typeof expression !== 'string') {
        return { valid: false, error: 'Expression is required' };
      }
      
      // Clean the expression
      const cleanExpr = expression.trim();
      
      if (cleanExpr.length === 0) {
        return { valid: false, error: 'Expression cannot be empty' };
      }
      
      // Check for dangerous patterns
      const dangerousPatterns = [
        /eval\s*\(/i,
        /function\s*\(/i,
        /=>/,
        /require\s*\(/i,
        /import\s/i,
        /process\./i,
        /global\./i,
        /__/
      ];
      
      for (const pattern of dangerousPatterns) {
        if (pattern.test(cleanExpr)) {
          return { valid: false, error: 'Expression contains forbidden patterns' };
        }
      }
      
      // Create test scope with sample values
      const testScope = {};
      if (Array.isArray(inputColumns)) {
        inputColumns.forEach(col => {
          testScope[col] = 1; // Use 1 as test value
        });
      }
      
      // Try to parse the expression
      const parsed = math.parse(cleanExpr);
      
      // Get variables used in expression
      const usedVariables = new Set();
      parsed.traverse(node => {
        if (node.type === 'SymbolNode') {
          usedVariables.add(node.name);
        }
      });
      
      // Filter out math.js built-in functions
      const mathFunctions = new Set([
        'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh',
        'log', 'log10', 'log2', 'exp', 'sqrt', 'abs', 'ceil', 'floor', 'round',
        'min', 'max', 'sum', 'mean', 'median', 'std', 'pow', 'mod',
        'pi', 'e', 'true', 'false', 'null', 'if'
      ]);
      
      const requiredVariables = [];
      usedVariables.forEach(v => {
        if (!mathFunctions.has(v)) {
          requiredVariables.push(v);
        }
      });
      
      // Warn about unused input columns
      const unusedInputs = inputColumns.filter(col => !usedVariables.has(col));
      
      // Try to evaluate with test values
      try {
        const compiled = parsed.compile();
        const allVarsScope = {};
        requiredVariables.forEach(v => { allVarsScope[v] = 1; });
        compiled.evaluate(allVarsScope);
      } catch (evalError) {
        return { 
          valid: false, 
          error: `Formula evaluation error: ${evalError.message}` 
        };
      }
      
      return {
        valid: true,
        requiredVariables,
        unusedInputs: unusedInputs.length > 0 ? unusedInputs : undefined
      };
      
    } catch (error) {
      return {
        valid: false,
        error: `Invalid formula syntax: ${error.message}`
      };
    }
  },

  /**
   * Evaluate a formula with given values
   * @param {string} expression - Formula expression
   * @param {Object} values - Variable values { column_name: value }
   * @returns {Object} Evaluation result
   */
  evaluate(expression, values) {
    try {
      // Create scope with custom functions
      const scope = {
        ...values,
        // Add custom helper functions
        IF: (condition, trueVal, falseVal) => condition ? trueVal : falseVal,
        ROUND: (val, decimals = 2) => Math.round(val * Math.pow(10, decimals)) / Math.pow(10, decimals),
        PERCENTAGE: (part, whole) => whole !== 0 ? (part / whole) * 100 : 0,
        GROWTH: (newVal, oldVal) => oldVal !== 0 ? ((newVal - oldVal) / oldVal) * 100 : 0
      };
      
      // Parse and evaluate
      const result = math.evaluate(expression, scope);
      
      // Handle special result types
      let finalResult;
      if (typeof result === 'object' && result !== null) {
        // Matrix or complex result
        finalResult = math.format(result, { precision: 6 });
      } else if (typeof result === 'number') {
        // Round to avoid floating point issues
        finalResult = Math.round(result * 1000000) / 1000000;
      } else {
        finalResult = result;
      }
      
      return {
        success: true,
        value: finalResult
      };
      
    } catch (error) {
      return {
        success: false,
        error: error.message,
        value: null
      };
    }
  },

  /**
   * Apply formula to multiple rows of data
   * @param {string} expression - Formula expression
   * @param {Array} data - Array of data objects
   * @param {Object} columnMapping - Map formula variables to data columns
   * @param {string} outputColumn - Name of output column
   * @returns {Object} Results
   */
  applyToData(expression, data, columnMapping = {}, outputColumn = 'result') {
    const results = [];
    const errors = [];
    
    data.forEach((row, index) => {
      try {
        // Map columns
        const values = {};
        for (const [formulaVar, dataCol] of Object.entries(columnMapping)) {
          values[formulaVar] = row[dataCol];
        }
        
        // If no mapping, use row directly
        const inputValues = Object.keys(columnMapping).length > 0 ? values : row;
        
        const evalResult = this.evaluate(expression, inputValues);
        
        if (evalResult.success) {
          results.push({
            rowIndex: index,
            [outputColumn]: evalResult.value
          });
        } else {
          errors.push({
            rowIndex: index,
            error: evalResult.error
          });
        }
      } catch (err) {
        errors.push({
          rowIndex: index,
          error: err.message
        });
      }
    });
    
    return {
      success: errors.length === 0,
      results,
      errors,
      processedCount: results.length,
      errorCount: errors.length
    };
  },

  /**
   * Get list of supported functions
   * @returns {Array} List of functions with descriptions
   */
  getSupportedFunctions() {
    return [
      { name: '+', description: 'Addition', example: 'a + b' },
      { name: '-', description: 'Subtraction', example: 'a - b' },
      { name: '*', description: 'Multiplication', example: 'a * b' },
      { name: '/', description: 'Division', example: 'a / b' },
      { name: '^', description: 'Power', example: 'a ^ 2' },
      { name: 'sqrt(x)', description: 'Square root', example: 'sqrt(16)' },
      { name: 'abs(x)', description: 'Absolute value', example: 'abs(-5)' },
      { name: 'round(x)', description: 'Round to nearest integer', example: 'round(3.7)' },
      { name: 'floor(x)', description: 'Round down', example: 'floor(3.7)' },
      { name: 'ceil(x)', description: 'Round up', example: 'ceil(3.2)' },
      { name: 'min(a,b)', description: 'Minimum value', example: 'min(5, 3)' },
      { name: 'max(a,b)', description: 'Maximum value', example: 'max(5, 3)' },
      { name: 'sum(a,b,c)', description: 'Sum of values', example: 'sum(1, 2, 3)' },
      { name: 'mean(a,b,c)', description: 'Average', example: 'mean(1, 2, 3)' },
      { name: 'log(x)', description: 'Natural logarithm', example: 'log(10)' },
      { name: 'log10(x)', description: 'Base 10 logarithm', example: 'log10(100)' },
      { name: 'IF(cond,t,f)', description: 'Conditional', example: 'IF(a > 0, a, 0)' },
      { name: 'ROUND(x,d)', description: 'Round to decimals', example: 'ROUND(3.14159, 2)' },
      { name: 'PERCENTAGE(p,w)', description: 'Calculate percentage', example: 'PERCENTAGE(25, 100)' },
      { name: 'GROWTH(new,old)', description: 'Growth percentage', example: 'GROWTH(110, 100)' }
    ];
  }
};

module.exports = formulaEngine;
