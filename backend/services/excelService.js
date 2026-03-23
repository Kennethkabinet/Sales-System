const ExcelJS = require('exceljs');
const path = require('path');
const fs = require('fs');

const indexToExcelCol = (index) => {
  let n = index + 1;
  let col = '';
  while (n > 0) {
    const rem = (n - 1) % 26;
    col = String.fromCharCode(65 + rem) + col;
    n = Math.floor((n - 1) / 26);
  }
  return col;
};

const worksheetToAoa = (worksheet, { defval = '' } = {}) => {
  if (!worksheet) return [];
  const maxCols = Math.max(
    worksheet.columnCount || 0,
    worksheet.getRow(1)?.cellCount || 0
  );
  const rows = [];
  worksheet.eachRow({ includeEmpty: true }, (row, rowNumber) => {
    const rowArr = [];
    for (let c = 1; c <= maxCols; c++) {
      const cell = row.getCell(c);
      const value = cell?.value;

      if (value === null || value === undefined) {
        rowArr.push(defval);
        continue;
      }

      if (typeof value === 'object') {
        if (value.richText) {
          rowArr.push(value.richText.map((t) => t.text).join(''));
        } else if (value.formula !== undefined) {
          rowArr.push(value.result ?? defval);
        } else if (value.text !== undefined) {
          rowArr.push(value.text);
        } else {
          rowArr.push(cell.text ?? String(value));
        }
      } else {
        rowArr.push(value);
      }
    }
    rows[rowNumber - 1] = rowArr;
  });
  return rows;
};

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
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.readFile(filePath);

      const worksheet = workbook.worksheets[0];
      const rawData = worksheetToAoa(worksheet, { defval: '' });
      
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
        const excelCol = indexToExcelCol(index); // A, B, C, etc.
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
      const workbook = new ExcelJS.Workbook();
      const worksheet = workbook.addWorksheet('Data');

      data.forEach((row) => {
        const rowData = Array.isArray(columns) && columns.length > 0
          ? columns.map((col) => row[col] ?? '')
          : Object.values(row);
        worksheet.addRow(rowData);
      });
      
      // Generate output path
      const outputDir = path.join(__dirname, '../exports');
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }
      
      const outputPath = path.join(outputDir, `${filename}_${Date.now()}.xlsx`);

      await workbook.xlsx.writeFile(outputPath);
      
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
      const workbook = new ExcelJS.Workbook();
      await workbook.xlsx.readFile(filePath);
      const worksheet = workbook.worksheets[0];
      const rawData = worksheetToAoa(worksheet, { defval: '' });
      
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
