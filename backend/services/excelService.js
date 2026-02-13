const XLSX = require('xlsx');
const path = require('path');
const fs = require('fs');

/**
 * Excel Service - Handles Excel file parsing and export
 */
const excelService = {
  /**
   * Parse an Excel file and extract data
   * @param {string} filePath - Path to the Excel file
   * @param {Object} columnMapping - Optional mapping of Excel columns to field names
   * @returns {Object} Parsed data with columns and rows
   */
  async parseExcel(filePath, columnMapping = {}) {
    try {
      // Read the workbook
      const workbook = XLSX.readFile(filePath);
      
      // Get first sheet
      const sheetName = workbook.SheetNames[0];
      const worksheet = workbook.Sheets[sheetName];
      
      // Convert to JSON (array of objects)
      const rawData = XLSX.utils.sheet_to_json(worksheet, { 
        header: 1,
        defval: ''  // Default value for empty cells
      });
      
      if (rawData.length === 0) {
        return {
          success: false,
          error: 'Excel file is empty'
        };
      }
      
      // First row is headers
      const headers = rawData[0];
      const dataRows = rawData.slice(1);
      
      // Determine column names
      const columns = [];
      const columnMap = {};
      
      headers.forEach((header, index) => {
        const excelCol = XLSX.utils.encode_col(index); // A, B, C, etc.
        let fieldName;
        
        if (columnMapping[excelCol]) {
          // Use provided mapping
          fieldName = columnMapping[excelCol];
        } else if (columnMapping[header]) {
          // Map by header name
          fieldName = columnMapping[header];
        } else {
          // Use header as field name, cleaned up
          fieldName = String(header)
            .toLowerCase()
            .replace(/[^a-z0-9]+/g, '_')
            .replace(/^_|_$/g, '');
          
          // Ensure unique field name
          if (!fieldName || columns.includes(fieldName)) {
            fieldName = `column_${index + 1}`;
          }
        }
        
        columns.push(fieldName);
        columnMap[index] = fieldName;
      });
      
      // Parse data rows
      const data = dataRows
        .filter(row => row.some(cell => cell !== '')) // Skip empty rows
        .map(row => {
          const rowData = {};
          row.forEach((cell, index) => {
            const fieldName = columnMap[index];
            if (fieldName) {
              // Try to parse numbers
              if (typeof cell === 'string') {
                const num = parseFloat(cell.replace(/[,$]/g, ''));
                rowData[fieldName] = !isNaN(num) && cell.match(/^[\d,.$-]+$/) ? num : cell;
              } else {
                rowData[fieldName] = cell;
              }
            }
          });
          return rowData;
        });
      
      return {
        success: true,
        columns,
        data,
        rowCount: data.length
      };
      
    } catch (error) {
      console.error('Excel parse error:', error);
      return {
        success: false,
        error: `Failed to parse Excel file: ${error.message}`
      };
    }
  },

  /**
   * Export data to Excel file
   * @param {string} filename - Output filename
   * @param {Array} columns - Column names
   * @param {Array} data - Array of data objects
   * @returns {string} Path to exported file
   */
  async exportToExcel(filename, columns, data) {
    try {
      // Create workbook
      const workbook = XLSX.utils.book_new();
      
      // Prepare data with headers
      const exportData = [columns.length > 0 ? columns : Object.keys(data[0] || {})];
      
      data.forEach(row => {
        const rowData = columns.length > 0 
          ? columns.map(col => row[col] ?? '')
          : Object.values(row);
        exportData.push(rowData);
      });
      
      // Create worksheet
      const worksheet = XLSX.utils.aoa_to_sheet(exportData);
      
      // Add to workbook
      XLSX.utils.book_append_sheet(workbook, worksheet, 'Data');
      
      // Generate output path
      const outputDir = path.join(__dirname, '../exports');
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      
      const outputPath = path.join(outputDir, `${filename}_${Date.now()}.xlsx`);
      
      // Write file
      XLSX.writeFile(workbook, outputPath);
      
      return outputPath;
      
    } catch (error) {
      console.error('Excel export error:', error);
      throw new Error(`Failed to export Excel file: ${error.message}`);
    }
  },

  /**
   * Validate Excel file structure
   * @param {string} filePath - Path to Excel file
   * @param {Array} requiredColumns - Required column names
   * @returns {Object} Validation result
   */
  async validateStructure(filePath, requiredColumns = []) {
    try {
      const workbook = XLSX.readFile(filePath);
      const sheetName = workbook.SheetNames[0];
      const worksheet = workbook.Sheets[sheetName];
      const rawData = XLSX.utils.sheet_to_json(worksheet, { header: 1 });
      
      if (rawData.length === 0) {
        return { valid: false, error: 'File is empty' };
      }
      
      const headers = rawData[0].map(h => String(h).toLowerCase().trim());
      
      const missingColumns = requiredColumns.filter(
        col => !headers.includes(col.toLowerCase())
      );
      
      if (missingColumns.length > 0) {
        return {
          valid: false,
          error: `Missing required columns: ${missingColumns.join(', ')}`,
          missingColumns
        };
      }
      
      return {
        valid: true,
        headers: rawData[0],
        rowCount: rawData.length - 1
      };
      
    } catch (error) {
      return {
        valid: false,
        error: `Cannot read file: ${error.message}`
      };
    }
  },

  /**
   * Get preview of Excel file (first N rows)
   * @param {string} filePath - Path to Excel file
   * @param {number} rows - Number of rows to preview
   * @returns {Object} Preview data
   */
  async getPreview(filePath, rows = 5) {
    const result = await this.parseExcel(filePath);
    
    if (!result.success) {
      return result;
    }
    
    return {
      success: true,
      columns: result.columns,
      preview: result.data.slice(0, rows),
      totalRows: result.data.length
    };
  }
};

module.exports = excelService;
