import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import '../services/api_service.dart';

/// Sheet model for spreadsheet data
class SheetModel {
  final int id;
  final String name;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool shownToViewers;
  final int? lockedBy;
  final String? lockedByName;
  final DateTime? lockedAt;
  final int? editingUserId;
  final String? editingUserName;

  SheetModel({
    required this.id,
    required this.name,
    this.columns = const [],
    this.rows = const [],
    this.createdAt,
    this.updatedAt,
    this.shownToViewers = false,
    this.lockedBy,
    this.lockedByName,
    this.lockedAt,
    this.editingUserId,
    this.editingUserName,
  });

  factory SheetModel.fromJson(Map<String, dynamic> json) {
    return SheetModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? 'Untitled',
      columns: json['columns'] != null 
          ? List<String>.from(json['columns']) 
          : [],
      rows: json['rows'] != null
          ? List<Map<String, dynamic>>.from(
              (json['rows'] as List).map((r) => Map<String, dynamic>.from(r)))
          : [],
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : null,
      shownToViewers: json['shown_to_viewers'] ?? false,
      lockedBy: json['locked_by'],
      lockedByName: json['locked_by_name'],
      lockedAt: json['locked_at'] != null 
          ? DateTime.parse(json['locked_at']) 
          : null,
      editingUserId: json['editing_user_id'],
      editingUserName: json['editing_user_name'],
    );
  }

  bool get isLocked => lockedBy != null;
  bool get isBeingEdited => editingUserId != null;
}

class SheetScreen extends StatefulWidget {
  final bool readOnly;
  
  const SheetScreen({super.key, this.readOnly = false});

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  List<SheetModel> _sheets = [];
  SheetModel? _currentSheet;
  bool _isLoading = true;
  String? _error;
  
  // Collaborative editing state
  bool _isLocked = false;
  String? _lockedByUser;
  bool _isEditingSession = false;
  List<String> _activeEditors = [];
  
  // Spreadsheet state
  List<String> _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  List<Map<String, String>> _data = [];
  List<String> _rowLabels = []; // Custom row labels
  int? _editingRow;
  int? _editingCol;
  final _editController = TextEditingController();
  final _formulaBarController = TextEditingController();
  final _focusNode = FocusNode();
  final _formulaBarFocusNode = FocusNode();
  final _spreadsheetFocusNode = FocusNode();
  int? _selectedRow;
  int? _selectedCol;
  
  // Multi-cell selection range (Excel-like drag select)
  int? _selectionEndRow;
  int? _selectionEndCol;
  bool _isDragging = false;
  
  // Column widths for resizable columns
  final Map<int, double> _columnWidths = {};
  static const double _defaultCellWidth = 120.0;
  static const double _minCellWidth = 50.0;
  static const double _rowNumWidth = 50.0;
  static const double _cellHeight = 32.0;
  static const double _headerHeight = 36.0;
  bool _isResizingColumn = false;
  int? _resizingColumnIndex;
  double _resizingStartX = 0;
  double _resizingStartWidth = 0;
  
  // Scroll controllers for synchronized scrolling
  final _horizontalScrollController = ScrollController();
  final _verticalScrollController = ScrollController();
  
  // Timer for periodic status updates
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _initializeSheet();
    _loadSheets();
    
    // Set up periodic status refresh (every 30 seconds)
    _statusTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshSheetStatus();
    });
  }

  // =============== Collaborative Editing Features ===============

  /// Toggle sheet visibility to viewers (Admin only)
  Future<void> _toggleSheetVisibility(int sheetId, bool showToViewers) async {
    try {
      await ApiService.toggleSheetVisibility(sheetId, showToViewers);
      await _loadSheets(); // Refresh sheets list
      await _refreshSheetStatus(); // Refresh current sheet status
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              showToViewers 
                ? 'Sheet is now visible to viewers' 
                : 'Sheet is now hidden from viewers'
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update visibility: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Lock sheet for editing
  Future<void> _lockSheet() async {
    if (_currentSheet == null) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.lockSheet(_currentSheet!.id);
      await _refreshSheetStatus();
      await _startEditSession();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sheet locked for editing'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to lock sheet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Unlock sheet
  Future<void> _unlockSheet() async {
    if (_currentSheet == null) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.unlockSheet(_currentSheet!.id);
      await _refreshSheetStatus();
      
      setState(() => _isEditingSession = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sheet unlocked'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to unlock sheet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Start edit session
  Future<void> _startEditSession() async {
    if (_currentSheet == null) return;

    try {
      await ApiService.startEditSession(_currentSheet!.id);
      setState(() => _isEditingSession = true);
      
      // Start periodic heartbeat
      _startEditSessionHeartbeat();
    } catch (e) {
      print('Failed to start edit session: $e');
    }
  }

  /// Periodic heartbeat for edit session
  void _startEditSessionHeartbeat() {
    if (!_isEditingSession || _currentSheet == null) return;
    
    Future.delayed(const Duration(minutes: 2), () async {
      if (_isEditingSession && _currentSheet != null && mounted) {
        try {
          await ApiService.startEditSession(_currentSheet!.id);
          _startEditSessionHeartbeat();
        } catch (e) {
          print('Edit session heartbeat failed: $e');
        }
      }
    });
  }

  /// Refresh sheet status (locks and active editors)
  Future<void> _refreshSheetStatus() async {
    if (_currentSheet == null) return;

    try {
      final response = await ApiService.getSheetStatus(_currentSheet!.id);
      final status = response['status'];
      
      setState(() {
        _isLocked = status['is_locked'] ?? false;
        _lockedByUser = status['locked_by'];
        _activeEditors = (status['active_editors'] as List<dynamic>?)
            ?.map((e) => e['username'] as String)
            .toList() ?? [];
      });
    } catch (e) {
      print('Failed to refresh sheet status: $e');
    }
  }

  // =============== Original Methods ===============

  void _initializeSheet() {
    // Initialize with 100 empty rows
    _data = List.generate(100, (index) {
      final row = <String, String>{};
      for (var col in _columns) {
        row[col] = '';
      }
      return row;
    });
    // Initialize row labels
    _rowLabels = List.generate(100, (index) => '${index + 1}');
  }

  Future<void> _loadSheets() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiService.getSheets();
      setState(() {
        _sheets = (response['sheets'] as List?)
            ?.map((s) => SheetModel.fromJson(s))
            .toList() ?? [];
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSheetData(int sheetId) async {
    setState(() => _isLoading = true);

    try {
      final response = await ApiService.getSheetData(sheetId);
      final sheet = SheetModel.fromJson(response['sheet']);
      
      setState(() {
        _currentSheet = sheet;
        if (sheet.columns.isNotEmpty) {
          _columns = List<String>.from(sheet.columns);
        } else {
          _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
        }
        
        if (sheet.rows.isNotEmpty) {
          _data = sheet.rows.map((r) {
            final row = <String, String>{};
            for (var col in _columns) {
              row[col] = r[col]?.toString() ?? '';
            }
            return row;
          }).toList();
          // Ensure minimum 100 rows
          while (_data.length < 100) {
            final row = <String, String>{};
            for (var col in _columns) {
              row[col] = '';
            }
            _data.add(row);
          }
        } else {
          // Initialize empty data if no rows
          _data = List.generate(100, (index) {
            final row = <String, String>{};
            for (var col in _columns) {
              row[col] = '';
            }
            return row;
          });
        }
        
        // Reset row labels to match data length
        _rowLabels = List.generate(_data.length, (index) => '${index + 1}');
        
        // Clear selections
        _selectedRow = null;
        _selectedCol = null;
        _selectionEndRow = null;
        _selectionEndCol = null;
        _editingRow = null;
        _editingCol = null;
        _isLoading = false;
      });
      
      // Refresh collaborative editing status
      await _refreshSheetStatus();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _createNewSheet() async {
    final name = await _showNameDialog('New Sheet', 'Enter sheet name');
    if (name == null || name.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      // Reset to default columns for new sheet
      final defaultColumns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
      final response = await ApiService.createSheet(name, defaultColumns);
      final sheet = SheetModel.fromJson(response['sheet']);
      setState(() {
        _sheets.insert(0, sheet);
        _currentSheet = sheet;
        // Reset columns to default
        _columns = List<String>.from(defaultColumns);
        // Clear all data and reinitialize
        _data = List.generate(100, (index) {
          final row = <String, String>{};
          for (var col in _columns) {
            row[col] = '';
          }
          return row;
        });
        // Reset row labels
        _rowLabels = List.generate(100, (index) => '${index + 1}');
        // Clear selections
        _selectedRow = null;
        _selectedCol = null;
        _selectionEndRow = null;
        _selectionEndCol = null;
        _editingRow = null;
        _editingCol = null;
        _isLoading = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New sheet created'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create sheet: $e')),
        );
      }
    }
  }

  Future<void> _saveSheet() async {
    if (_currentSheet == null) {
      await _createNewSheet();
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Filter out empty rows for saving
      final nonEmptyRows = _data.where((row) {
        return row.values.any((v) => v.isNotEmpty);
      }).toList();

      await ApiService.updateSheet(
        _currentSheet!.id,
        _currentSheet!.name,
        _columns,
        nonEmptyRows,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sheet saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _showNameDialog(String title, String hint, {String? initialValue}) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: hint,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameColumn(int colIndex) async {
    final currentName = _columns[colIndex];
    final newName = await _showNameDialog(
      'Rename Column',
      'Enter new column name',
      initialValue: currentName,
    );
    
    if (newName == null || newName.isEmpty || newName == currentName) return;
    
    // Check for duplicate names
    if (_columns.contains(newName)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Column name already exists'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    setState(() {
      // Update column name
      final oldName = _columns[colIndex];
      _columns[colIndex] = newName;
      
      // Update all row data with new column name
      for (var row in _data) {
        if (row.containsKey(oldName)) {
          row[newName] = row[oldName]!;
          row.remove(oldName);
        }
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Column renamed to "$newName"'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _renameRow(int rowIndex) async {
    final currentLabel = _rowLabels[rowIndex];
    final newLabel = await _showNameDialog(
      'Rename Row',
      'Enter new row label',
      initialValue: currentLabel,
    );
    
    if (newLabel == null || newLabel.isEmpty || newLabel == currentLabel) return;
    
    setState(() {
      _rowLabels[rowIndex] = newLabel;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Row renamed to "$newLabel"'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _confirmDeleteSheet(SheetModel sheet) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';
    
    // Check permissions - only admin and manager can delete
    if (userRole != 'admin' && userRole != 'manager') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to delete sheets'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sheet'),
        content: Text(
          'Are you sure you want to delete "${sheet.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _deleteSheet(sheet.id);
    }
  }

  Future<void> _deleteSheet(int sheetId) async {
    setState(() => _isLoading = true);

    try {
      await ApiService.deleteSheet(sheetId);
      
      // If the deleted sheet was the current sheet, clear it
      if (_currentSheet?.id == sheetId) {
        setState(() {
          _currentSheet = null;
          // Reset to default columns
          _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
          // Clear all data
          _data = List.generate(100, (index) {
            final row = <String, String>{};
            for (var col in _columns) {
              row[col] = '';
            }
            return row;
          });
          // Reset row labels
          _rowLabels = List.generate(100, (index) => '${index + 1}');
          // Clear selections
          _selectedRow = null;
          _selectedCol = null;
          _selectionEndRow = null;
          _selectionEndCol = null;
          _editingRow = null;
          _editingCol = null;
        });
      }

      // Reload the sheets list
      await _loadSheets();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sheet deleted successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete sheet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addColumn() async {
    // Generate next column letter
    String nextCol;
    if (_columns.isEmpty) {
      nextCol = 'A';
    } else {
      final lastCol = _columns.last;
      if (lastCol.length == 1 && lastCol.codeUnitAt(0) < 90) {
        nextCol = String.fromCharCode(lastCol.codeUnitAt(0) + 1);
      } else {
        nextCol = 'A${_columns.length + 1}';
      }
    }

    setState(() {
      _columns.add(nextCol);
      for (var row in _data) {
        row[nextCol] = '';
      }
    });
  }

  void _addRow() {
    setState(() {
      final row = <String, String>{};
      for (var col in _columns) {
        row[col] = '';
      }
      _data.add(row);
      // Add label for new row
      _rowLabels.add('${_data.length}');
    });
  }

  void _deleteColumn() {
    if (_selectedCol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a column to delete'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_columns.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete the last column'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final colToDelete = _columns[_selectedCol!];
    
    setState(() {
      _columns.removeAt(_selectedCol!);
      // Remove column data from all rows
      for (var row in _data) {
        row.remove(colToDelete);
      }
      _selectedCol = null;
      _selectionEndCol = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Column $colToDelete deleted'),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _deleteRow() {
    if (_selectedRow == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a row to delete'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Don't allow deleting if only a few rows left
    if (_data.length <= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot delete row - minimum 10 rows required'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final rowNum = _selectedRow! + 1;
    
    setState(() {
      _data.removeAt(_selectedRow!);
      _rowLabels.removeAt(_selectedRow!);
      _selectedRow = null;
      _selectionEndRow = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Row $rowNum deleted'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _exportSheet(String format) async {
    if (_currentSheet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No sheet selected to export'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final fileBytes = await ApiService.exportSheet(_currentSheet!.id, format: format);
      
      // Save file
      final fileName = '${_currentSheet!.name.replaceAll(' ', '_')}.$format';
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save file',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [format],
      );

      if (outputPath != null) {
        final file = File(outputPath);
        await file.writeAsBytes(fileBytes);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Sheet exported successfully to $outputPath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to export: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importSheet() async {
    if (_currentSheet == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select or create a sheet first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        if (file.bytes != null) {
          // For now, show a message that they should use the backend import
          // A full implementation would parse the Excel file here
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Import feature: Please use CSV format or contact administrator'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to import: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showExportMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Sheet'),
        content: const Text('Choose export format:'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportSheet('xlsx');
            },
            child: const Text('Excel (.xlsx)'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportSheet('csv');
            },
            child: const Text('CSV (.csv)'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _startEditing(int row, int col) {
    // Prevent editing in read-only mode or for viewers
    if (widget.readOnly) return;
    final role = Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    if (role == 'viewer') return;
    
    setState(() {
      _editingRow = row;
      _editingCol = col;
      _editController.text = _data[row][_columns[col]] ?? '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _saveEdit() {
    if (_editingRow != null && _editingCol != null) {
      setState(() {
        _data[_editingRow!][_columns[_editingCol!]] = _editController.text;
        _editingRow = null;
        _editingCol = null;
        _updateFormulaBar();
      });
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingRow = null;
      _editingCol = null;
    });
  }

  // =============== Excel-like Selection Helpers ===============

  /// Get column width for a given column index
  double _getColumnWidth(int colIndex) {
    return _columnWidths[colIndex] ?? _defaultCellWidth;
  }

  /// Get cell reference string (e.g., "A1", "B3")
  String _getCellReference(int row, int col) {
    String colRef = '';
    int c = col;
    while (c >= 0) {
      colRef = String.fromCharCode(65 + (c % 26)) + colRef;
      c = (c ~/ 26) - 1;
    }
    return '$colRef${row + 1}';
  }

  /// Get normalized selection bounds (min/max regardless of drag direction)
  Map<String, int> _getSelectionBounds() {
    final startRow = _selectedRow ?? 0;
    final startCol = _selectedCol ?? 0;
    final endRow = _selectionEndRow ?? startRow;
    final endCol = _selectionEndCol ?? startCol;
    return {
      'minRow': startRow < endRow ? startRow : endRow,
      'maxRow': startRow > endRow ? startRow : endRow,
      'minCol': startCol < endCol ? startCol : endCol,
      'maxCol': startCol > endCol ? startCol : endCol,
    };
  }

  /// Check if a cell is within the current selection range
  bool _isInSelection(int row, int col) {
    if (_selectedRow == null || _selectedCol == null) return false;
    final bounds = _getSelectionBounds();
    return row >= bounds['minRow']! && row <= bounds['maxRow']! &&
           col >= bounds['minCol']! && col <= bounds['maxCol']!;
  }

  /// Check if there's a multi-cell selection (more than 1 cell)
  bool get _hasMultiSelection {
    if (_selectedRow == null || _selectedCol == null) return false;
    if (_selectionEndRow == null && _selectionEndCol == null) return false;
    return _selectionEndRow != _selectedRow || _selectionEndCol != _selectedCol;
  }

  /// Select a single cell and clear range
  void _selectCell(int row, int col) {
    setState(() {
      _selectedRow = row;
      _selectedCol = col;
      _selectionEndRow = row;
      _selectionEndCol = col;
      _updateFormulaBar();
    });
  }

  /// Update formula bar to show the active cell's content
  void _updateFormulaBar() {
    if (_selectedRow != null && _selectedCol != null) {
      final value = _data[_selectedRow!][_columns[_selectedCol!]] ?? '';
      _formulaBarController.text = value;
    } else {
      _formulaBarController.text = '';
    }
  }

  /// Clear selection of all selected cells (Delete key)
  void _clearSelectedCells() {
    if (widget.readOnly) return;
    final role = Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    if (role == 'viewer') return;
    
    final bounds = _getSelectionBounds();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _data[r][_columns[c]] = '';
        }
      }
      _updateFormulaBar();
    });
  }

  /// Convert row/col from a global position within the spreadsheet
  Map<String, int>? _getCellFromPosition(Offset localPosition) {
    // Account for row number column
    double x = localPosition.dx - _rowNumWidth;
    double y = localPosition.dy - _headerHeight;
    
    if (x < 0 || y < 0) return null;
    
    // Find column
    int col = -1;
    double accX = 0;
    for (int c = 0; c < _columns.length; c++) {
      final w = _getColumnWidth(c);
      if (x >= accX && x < accX + w) {
        col = c;
        break;
      }
      accX += w;
    }
    if (col == -1) return null;
    
    // Find row
    int row = (y / _cellHeight).floor();
    if (row < 0 || row >= _data.length) return null;
    
    return {'row': row, 'col': col};
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    
    if (_editingRow != null && _editingCol != null) {
      // In editing mode
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        _spreadsheetFocusNode.requestFocus();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        final row = _editingRow!;
        final col = _editingCol!;
        _saveEdit();
        // Move to next row
        if (row < _data.length - 1) {
          _selectCell(row + 1, col);
        }
        _spreadsheetFocusNode.requestFocus();
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        final row = _editingRow!;
        final col = _editingCol!;
        _saveEdit();
        // Move to next column
        if (col < _columns.length - 1) {
          _selectCell(row, col + 1);
        } else if (row < _data.length - 1) {
          _selectCell(row + 1, 0);
        }
        _spreadsheetFocusNode.requestFocus();
      }
    } else if (_selectedRow != null && _selectedCol != null) {
      // In selection mode
      
      // Ctrl+A: Select all cells
      if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyA) {
        setState(() {
          _selectedRow = 0;
          _selectedCol = 0;
          _selectionEndRow = _data.length - 1;
          _selectionEndCol = _columns.length - 1;
        });
        return;
      }
      
      // Ctrl+C: Copy selected cells
      if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection();
        return;
      }
      
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.f2) {
        _startEditing(_selectedRow!, _selectedCol!);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (isShift) {
          // Extend selection
          final endRow = (_selectionEndRow ?? _selectedRow!) - 1;
          if (endRow >= 0) {
            setState(() => _selectionEndRow = endRow);
          }
        } else if (_selectedRow! > 0) {
          _selectCell(_selectedRow! - 1, _selectedCol!);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (isShift) {
          final endRow = (_selectionEndRow ?? _selectedRow!) + 1;
          if (endRow < _data.length) {
            setState(() => _selectionEndRow = endRow);
          }
        } else if (_selectedRow! < _data.length - 1) {
          _selectCell(_selectedRow! + 1, _selectedCol!);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (isShift) {
          final endCol = (_selectionEndCol ?? _selectedCol!) - 1;
          if (endCol >= 0) {
            setState(() => _selectionEndCol = endCol);
          }
        } else if (_selectedCol! > 0) {
          _selectCell(_selectedRow!, _selectedCol! - 1);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (isShift) {
          final endCol = (_selectionEndCol ?? _selectedCol!) + 1;
          if (endCol < _columns.length) {
            setState(() => _selectionEndCol = endCol);
          }
        } else if (_selectedCol! < _columns.length - 1) {
          _selectCell(_selectedRow!, _selectedCol! + 1);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        if (_selectedCol! < _columns.length - 1) {
          _selectCell(_selectedRow!, _selectedCol! + 1);
        } else if (_selectedRow! < _data.length - 1) {
          _selectCell(_selectedRow! + 1, 0);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.delete ||
                 event.logicalKey == LogicalKeyboardKey.backspace) {
        _clearSelectedCells();
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        if (isCtrl) {
          _selectCell(0, 0);
        } else {
          _selectCell(_selectedRow!, 0);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.end) {
        if (isCtrl) {
          _selectCell(_data.length - 1, _columns.length - 1);
        } else {
          _selectCell(_selectedRow!, _columns.length - 1);
        }
      } else {
        // Start editing on any printable key press
        final key = event.character;
        if (key != null && key.length == 1 && !isCtrl) {
          _startEditing(_selectedRow!, _selectedCol!);
          _editController.text = key;
          _editController.selection = TextSelection.collapsed(offset: key.length);
        }
      }
    }
  }
  
  /// Copy selected cells to clipboard as tab-separated text
  void _copySelection() {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    final buffer = StringBuffer();
    for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
      final rowCells = <String>[];
      for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
        rowCells.add(_data[r][_columns[c]] ?? '');
      }
      buffer.writeln(rowCells.join('\t'));
    }
    Clipboard.setData(ClipboardData(text: buffer.toString().trimRight()));
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _editController.dispose();
    _formulaBarController.dispose();
    _focusNode.dispose();
    _formulaBarFocusNode.dispose();
    _spreadsheetFocusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          // Determine role-based access
          final role = auth.user?.role ?? '';
          final isViewer = role == 'viewer';
          final isReadOnly = widget.readOnly || isViewer;

          return Column(
            children: [
              // Toolbar
              _buildToolbar(),
              const Divider(height: 1),
              // Content
              Expanded(
                child: Row(
                  children: [
                    // Sheet list sidebar
                    _buildSheetList(),
                    const VerticalDivider(width: 1),
                    // Spreadsheet with status bar
                    Expanded(
                      child: Column(
                        children: [
                          // Status Bar
                          if (_currentSheet != null) _buildStatusBar(),
                          // Main content
                          Expanded(
                            child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _currentSheet == null
                                    ? _buildEmptyState()
                                    : _buildSpreadsheet(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Sheet Name - Flexible to prevent overflow
          Expanded(
            child: Row(
              children: [
                Icon(Icons.table_chart, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _currentSheet?.name ?? 'No Sheet Selected',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          
          // Compact buttons in a scrollable row
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // Export button (always visible)
                  _buildCompactButton(
                    icon: Icons.download,
                    label: 'Export',
                    onPressed: _showExportMenu,
                    color: Colors.green[700]!,
                  ),
                  
                  // Edit mode buttons (hidden in read-only mode or for viewers)
                  if (!widget.readOnly && Provider.of<AuthProvider>(context, listen: false).user?.role != 'viewer') ...[
                    const SizedBox(width: 4),
                    // New Sheet
                    _buildCompactButton(
                      icon: Icons.add,
                      label: 'New',
                      onPressed: _createNewSheet,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 4),
                    
                    // Import
                    _buildCompactButton(
                      icon: Icons.upload,
                      label: 'Import',
                      onPressed: _importSheet,
                      color: Colors.green[700]!,
                    ),
                    
                    _buildVerticalDivider(),
                    
                    // Collaborative editing controls
                    ..._buildCollaborativeControls(),
                    
                    _buildVerticalDivider(),
                    
                    // Columns
                    _buildCompactButton(
                      icon: Icons.view_column,
                      label: '+Col',
                      onPressed: _addColumn,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 4),
                    _buildCompactButton(
                      icon: Icons.remove,
                      label: '-Col',
                      onPressed: _deleteColumn,
                      color: Colors.red,
                    ),
                    
                    _buildVerticalDivider(),
                    
                    // Rows
                    _buildCompactButton(
                      icon: Icons.table_rows,
                      label: '+Row',
                      onPressed: _addRow,
                      color: Colors.indigo,
                    ),
                    const SizedBox(width: 4),
                    _buildCompactButton(
                      icon: Icons.remove,
                      label: '-Row',
                      onPressed: _deleteRow,
                      color: Colors.red,
                    ),
                    
                    _buildVerticalDivider(),
                    
                    // Save Button
                    ElevatedButton.icon(
                      onPressed: _saveSheet,
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Save', style: TextStyle(fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue[600],
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        elevation: 1,
                        minimumSize: const Size(0, 32),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(6),
            color: color.withOpacity(0.05),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build collaborative editing controls for toolbar
  List<Widget> _buildCollaborativeControls() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';
    final currentUserId = authProvider.user?.id ?? 0;
    final controls = <Widget>[];
    
    if (_currentSheet == null) return controls;
    
    // Show/Hide button for admin only
    if (userRole == 'admin') {
      controls.add(_buildCompactButton(
        icon: _currentSheet!.shownToViewers ? Icons.visibility : Icons.visibility_off,
        label: _currentSheet!.shownToViewers ? 'Hide' : 'Show',
        onPressed: () => _toggleSheetVisibility(
          _currentSheet!.id, 
          !_currentSheet!.shownToViewers
        ),
        color: _currentSheet!.shownToViewers ? Colors.orange : Colors.blue,
      ));
      controls.add(const SizedBox(width: 4));
    }
    
    // Lock/Unlock controls for editors and admins
    if (userRole == 'admin' || userRole == 'editor' || userRole == 'user') {
      if (_isLocked) {
        if (_lockedByUser != null && (_lockedByUser == authProvider.user?.username || userRole == 'admin')) {
          // Show unlock button for sheet owner or admin
          controls.add(_buildCompactButton(
            icon: Icons.lock_open,
            label: 'Unlock',
            onPressed: _unlockSheet,
            color: Colors.green,
          ));
        } else {
          // Show locked status
          controls.add(_buildCompactButton(
            icon: Icons.lock,
            label: 'Locked',
            onPressed: null,
            color: Colors.red,
          ));
        }
      } else {
        // Show lock button for editors
        controls.add(_buildCompactButton(
          icon: Icons.edit,
          label: 'Lock & Edit',
          onPressed: _lockSheet,
          color: Colors.blue,
        ));
      }
      controls.add(const SizedBox(width: 4));
    }
    
    return controls;
  }

  Widget _buildStatusBar() {
    if (_currentSheet == null) return const SizedBox();

    final hasLock = _isLocked && _lockedByUser != null && _lockedByUser!.isNotEmpty;
    final hasActiveEditors = _activeEditors.isNotEmpty;

    List<Widget> statusItems = [];

    // Lock status
    if (hasLock) {
      statusItems.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock,
              size: 16,
              color: Colors.red[600],
            ),
            const SizedBox(width: 4),
            Text(
              'Locked by $_lockedByUser',
              style: TextStyle(
                color: Colors.red[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // Active editors status
    if (hasActiveEditors) {
      if (statusItems.isNotEmpty) {
        statusItems.add(
          Container(
            height: 12,
            width: 1,
            color: Colors.grey[400],
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
        );
      }
      
      statusItems.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.green[500],
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _activeEditors.length == 1 
                  ? 'Currently being edited by ${_activeEditors.first}'
                  : 'Currently being edited by ${_activeEditors.length} users',
              style: TextStyle(
                color: Colors.green[700],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    // If no status to show
    if (statusItems.isEmpty) {
      return const SizedBox();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: Colors.blue[600],
          ),
          const SizedBox(width: 8),
          ...statusItems,
        ],
      ),
    );
  }

  Widget _buildVerticalDivider() {
    return Container(
      height: 24,
      width: 1,
      color: Colors.grey[300],
      margin: const EdgeInsets.symmetric(horizontal: 8),
    );
  }

  Widget _buildSheetList() {
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          right: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.folder_open, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                Text(
                  'My Sheets',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _sheets.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.description_outlined, 
                            size: 48, 
                            color: Colors.grey[400]
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No sheets yet',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final viewerRole = Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
                              return Text(
                                viewerRole == 'viewer'
                                    ? 'No sheets shared with you yet'
                                    : 'Click "New" to create',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                  fontSize: 12,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemCount: _sheets.length,
                    itemBuilder: (context, index) {
                      final sheet = _sheets[index];
                      final isSelected = _currentSheet?.id == sheet.id;
                      return Container(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.blue[50] : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: isSelected
                              ? Border.all(color: Colors.blue[200]!, width: 1)
                              : null,
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          leading: Icon(
                            Icons.table_chart,
                            size: 20,
                            color: isSelected ? Colors.blue[700] : Colors.grey[600],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  sheet.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                    color: isSelected ? Colors.blue[900] : Colors.grey[800],
                                  ),
                                ),
                              ),
                              // Status indicators
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Lock indicator
                                  if (sheet.isLocked && sheet.lockedByName != null)
                                    Tooltip(
                                      message: 'Locked by ${sheet.lockedByName}',
                                      child: Icon(
                                        Icons.lock,
                                        size: 12,
                                        color: Colors.red[500],
                                      ),
                                    ),
                                  
                                  // Editing indicator
                                  if (sheet.isBeingEdited && sheet.editingUserName != null) ...[
                                    if (sheet.isLocked && sheet.lockedByName != null)
                                      const SizedBox(width: 4),
                                    Tooltip(
                                      message: 'Being edited by ${sheet.editingUserName}',
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: Colors.green[500],
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: (() {
                            final r = Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
                            return r == 'admin' || r == 'editor' || r == 'manager';
                          }())
                            ? IconButton(
                                icon: const Icon(Icons.delete_outline, size: 16),
                                color: Colors.red[400],
                                tooltip: 'Delete sheet',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => _confirmDeleteSheet(sheet),
                              )
                            : null,
                          onTap: () => _loadSheetData(sheet.id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final role = Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    final isViewer = role == 'viewer';
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.table_chart_outlined,
            size: 120,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 24),
          Text(
            isViewer ? 'No Shared Sheets' : 'No Sheet Selected',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isViewer 
                ? 'Sheets shared by admin will appear here automatically'
                : 'Select a sheet from the sidebar or create a new one',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          if (!isViewer) ...[
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _createNewSheet,
              icon: const Icon(Icons.add),
              label: const Text('Create New Sheet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                textStyle: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // =============== Formula Bar (Excel-like) ===============
  
  Widget _buildFormulaBar() {
    final cellRef = (_selectedRow != null && _selectedCol != null)
        ? _getCellReference(_selectedRow!, _selectedCol!)
        : '';
    final isReadOnly = widget.readOnly || 
        (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '') == 'viewer';

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Cell reference box (e.g., "A1")
          Container(
            width: 70,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
              color: Colors.grey[50],
            ),
            child: Text(
              cellRef,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
                fontFamily: 'monospace',
              ),
            ),
          ),
          // fx icon
          Container(
            width: 28,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
            ),
            child: Text(
              'fx',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600],
              ),
            ),
          ),
          // Formula/content input
          Expanded(
            child: TextField(
              controller: _formulaBarController,
              focusNode: _formulaBarFocusNode,
              readOnly: isReadOnly,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: InputBorder.none,
                isDense: true,
              ),
              onTap: () {
                if (_selectedRow != null && _selectedCol != null && !isReadOnly) {
                  _startEditing(_selectedRow!, _selectedCol!);
                  _editController.text = _formulaBarController.text;
                }
              },
              onSubmitted: (value) {
                if (_selectedRow != null && _selectedCol != null && !isReadOnly) {
                  setState(() {
                    _data[_selectedRow!][_columns[_selectedCol!]] = value;
                    _editingRow = null;
                    _editingCol = null;
                  });
                  _spreadsheetFocusNode.requestFocus();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  // =============== Excel-like Spreadsheet ===============

  Widget _buildSpreadsheet() {
    return Column(
      children: [
        // Formula bar
        _buildFormulaBar(),
        // Spreadsheet grid
        Expanded(
          child: Focus(
            focusNode: _spreadsheetFocusNode,
            onKeyEvent: (node, event) {
              _handleKeyEvent(event);
              // Let the event propagate for text input in TextField
              if (_editingRow != null) return KeyEventResult.ignored;
              return KeyEventResult.handled;
            },
            child: GestureDetector(
              onTap: () {
                if (_editingRow != null) {
                  _saveEdit();
                }
                _spreadsheetFocusNode.requestFocus();
              },
              child: Scrollbar(
                controller: _verticalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: Scrollbar(
                  controller: _horizontalScrollController,
                  thumbVisibility: true,
                  trackVisibility: true,
                  notificationPredicate: (notification) => notification.depth == 1,
                  child: SingleChildScrollView(
                    controller: _verticalScrollController,
                    child: SingleChildScrollView(
                      controller: _horizontalScrollController,
                      scrollDirection: Axis.horizontal,
                      child: _buildSpreadsheetGrid(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Selection info bar at bottom
        _buildSelectionInfoBar(),
      ],
    );
  }

  Widget _buildSpreadsheetGrid() {
    // Calculate total width
    double totalWidth = _rowNumWidth;
    for (int c = 0; c < _columns.length; c++) {
      totalWidth += _getColumnWidth(c);
    }
    
    return GestureDetector(
      onPanStart: (details) {
        final cell = _getCellFromPosition(details.localPosition);
        if (cell != null) {
          if (_editingRow != null) _saveEdit();
          setState(() {
            _isDragging = true;
            _selectedRow = cell['row']!;
            _selectedCol = cell['col']!;
            _selectionEndRow = cell['row']!;
            _selectionEndCol = cell['col']!;
            _updateFormulaBar();
          });
        }
      },
      onPanUpdate: (details) {
        if (_isDragging) {
          final cell = _getCellFromPosition(details.localPosition);
          if (cell != null) {
            setState(() {
              _selectionEndRow = cell['row']!;
              _selectionEndCol = cell['col']!;
            });
          }
        }
      },
      onPanEnd: (details) {
        setState(() {
          _isDragging = false;
        });
        _spreadsheetFocusNode.requestFocus();
      },
      behavior: HitTestBehavior.translucent,
      child: SizedBox(
        width: totalWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            _buildHeaderRow(),
            // Data rows
            ..._data.asMap().entries.map((entry) {
              return _buildDataRow(entry.key);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F0F0),
        border: Border(
          bottom: BorderSide(color: Colors.grey[400]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Select-all button (top-left corner)
          GestureDetector(
            onTap: () {
              setState(() {
                _selectedRow = 0;
                _selectedCol = 0;
                _selectionEndRow = _data.length - 1;
                _selectionEndCol = _columns.length - 1;
              });
            },
            child: Container(
              width: _rowNumWidth,
              height: _headerHeight,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: Colors.grey[400]!, width: 1),
                  bottom: BorderSide(color: Colors.grey[400]!, width: 1),
                ),
                color: const Color(0xFFE0E0E0),
              ),
              child: const Center(
                child: Icon(Icons.select_all, size: 14, color: Colors.grey),
              ),
            ),
          ),
          // Column headers with resize handles
          ..._columns.asMap().entries.map((entry) {
            final colIndex = entry.key;
            final colWidth = _getColumnWidth(colIndex);
            final bounds = _getSelectionBounds();
            final isColSelected = _selectedRow != null &&
                colIndex >= bounds['minCol']! && colIndex <= bounds['maxCol']!;
            
            return GestureDetector(
              onTap: () {
                // Select entire column
                setState(() {
                  _selectedRow = 0;
                  _selectedCol = colIndex;
                  _selectionEndRow = _data.length - 1;
                  _selectionEndCol = colIndex;
                  _updateFormulaBar();
                });
                _spreadsheetFocusNode.requestFocus();
              },
              onDoubleTap: () => _renameColumn(colIndex),
              child: SizedBox(
                width: colWidth,
                height: _headerHeight,
                child: Stack(
                  children: [
                    // Header content
                    Container(
                      width: colWidth,
                      height: _headerHeight,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(color: Colors.grey[400]!, width: 1),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: isColSelected
                              ? [const Color(0xFF4472C4), const Color(0xFF3461B3)]
                              : [const Color(0xFFF5F5F5), const Color(0xFFE0E0E0)],
                        ),
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isColSelected ? Colors.white : Colors.grey[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Resize handle on right edge
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeColumn,
                        child: GestureDetector(
                          onHorizontalDragStart: (details) {
                            _isResizingColumn = true;
                            _resizingColumnIndex = colIndex;
                            _resizingStartX = details.globalPosition.dx;
                            _resizingStartWidth = colWidth;
                          },
                          onHorizontalDragUpdate: (details) {
                            if (_isResizingColumn && _resizingColumnIndex == colIndex) {
                              final delta = details.globalPosition.dx - _resizingStartX;
                              final newWidth = (_resizingStartWidth + delta).clamp(_minCellWidth, 500.0);
                              setState(() {
                                _columnWidths[colIndex] = newWidth;
                              });
                            }
                          },
                          onHorizontalDragEnd: (details) {
                            _isResizingColumn = false;
                            _resizingColumnIndex = null;
                          },
                          child: Container(
                            width: 6,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDataRow(int rowIndex) {
    final bounds = _getSelectionBounds();
    final isRowInSelection = _selectedRow != null &&
        rowIndex >= bounds['minRow']! && rowIndex <= bounds['maxRow']!;

    return Row(
      children: [
        // Row number header
        GestureDetector(
          onTap: () {
            // Select entire row
            setState(() {
              _selectedRow = rowIndex;
              _selectedCol = 0;
              _selectionEndRow = rowIndex;
              _selectionEndCol = _columns.length - 1;
              _updateFormulaBar();
            });
            _spreadsheetFocusNode.requestFocus();
          },
          onDoubleTap: () => _renameRow(rowIndex),
          child: Container(
            width: _rowNumWidth,
            height: _cellHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(color: Colors.grey[400]!, width: 1),
                bottom: BorderSide(color: Colors.grey[300]!, width: 1),
              ),
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: isRowInSelection
                    ? [const Color(0xFF4472C4), const Color(0xFF3461B3)]
                    : [const Color(0xFFF5F5F5), const Color(0xFFE8E8E8)],
              ),
            ),
            child: Text(
              _rowLabels[rowIndex],
              style: TextStyle(
                fontSize: 11,
                fontWeight: isRowInSelection ? FontWeight.bold : FontWeight.w500,
                color: isRowInSelection ? Colors.white : Colors.grey[600],
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ),
        // Data cells
        ..._columns.asMap().entries.map((entry) {
          final colIndex = entry.key;
          final colName = entry.value;
          final colWidth = _getColumnWidth(colIndex);
          final isEditing = _editingRow == rowIndex && _editingCol == colIndex;
          final isActiveCell = _selectedRow == rowIndex && _selectedCol == colIndex;
          final isInSel = _isInSelection(rowIndex, colIndex);
          final value = _data[rowIndex][colName] ?? '';

          return GestureDetector(
            onTap: () {
              if (_isResizingColumn) return;
              if (_editingRow != null) _saveEdit();
              final isShift = HardwareKeyboard.instance.isShiftPressed;
              if (isShift && _selectedRow != null && _selectedCol != null) {
                // Shift+click: extend selection
                setState(() {
                  _selectionEndRow = rowIndex;
                  _selectionEndCol = colIndex;
                });
              } else {
                _selectCell(rowIndex, colIndex);
              }
              _spreadsheetFocusNode.requestFocus();
            },
            onDoubleTap: () {
              if (_isResizingColumn) return;
              _startEditing(rowIndex, colIndex);
            },
            child: Container(
              width: colWidth,
              height: _cellHeight,
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                  bottom: BorderSide(
                    color: Colors.grey[300]!,
                    width: 1,
                  ),
                ),
                color: isEditing
                    ? Colors.white
                    : isActiveCell
                        ? Colors.white
                        : isInSel
                            ? const Color(0xFFD6E4F0) // Excel blue selection
                            : (rowIndex % 2 == 0 ? Colors.white : const Color(0xFFFAFAFA)),
              ),
              child: Stack(
                children: [
                  // Cell content
                  if (isEditing)
                    TextField(
                      controller: _editController,
                      focusNode: _focusNode,
                      style: const TextStyle(fontSize: 13, fontFamily: 'Segoe UI'),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        border: InputBorder.none,
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      onSubmitted: (_) {
                        _saveEdit();
                        if (rowIndex < _data.length - 1) {
                          _selectCell(rowIndex + 1, colIndex);
                        }
                        _spreadsheetFocusNode.requestFocus();
                      },
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                      child: Align(
                        alignment: _isNumeric(value) ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black87,
                            fontFamily: 'Segoe UI',
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ),
                  // Active cell border (thick blue like Excel)
                  if (isActiveCell && !isEditing)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: const Color(0xFF1A73E8),
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Selection border (thin blue for range)
                  if (isInSel && !isActiveCell)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: _isSelectionEdge(rowIndex, colIndex, 'top')
                                  ? const BorderSide(color: Color(0xFF1A73E8), width: 1.5)
                                  : BorderSide.none,
                              bottom: _isSelectionEdge(rowIndex, colIndex, 'bottom')
                                  ? const BorderSide(color: Color(0xFF1A73E8), width: 1.5)
                                  : BorderSide.none,
                              left: _isSelectionEdge(rowIndex, colIndex, 'left')
                                  ? const BorderSide(color: Color(0xFF1A73E8), width: 1.5)
                                  : BorderSide.none,
                              right: _isSelectionEdge(rowIndex, colIndex, 'right')
                                  ? const BorderSide(color: Color(0xFF1A73E8), width: 1.5)
                                  : BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  /// Check if a cell is on the edge of the selection range
  bool _isSelectionEdge(int row, int col, String edge) {
    final bounds = _getSelectionBounds();
    switch (edge) {
      case 'top': return row == bounds['minRow']!;
      case 'bottom': return row == bounds['maxRow']!;
      case 'left': return col == bounds['minCol']!;
      case 'right': return col == bounds['maxCol']!;
      default: return false;
    }
  }

  /// Check if a value looks numeric (right-align like Excel)
  bool _isNumeric(String value) {
    if (value.isEmpty) return false;
    return double.tryParse(value.replaceAll(',', '')) != null;
  }

  /// Bottom info bar showing selection info (like Excel status bar)
  Widget _buildSelectionInfoBar() {
    String info = '';
    if (_hasMultiSelection) {
      final bounds = _getSelectionBounds();
      final rowCount = bounds['maxRow']! - bounds['minRow']! + 1;
      final colCount = bounds['maxCol']! - bounds['minCol']! + 1;
      final cellCount = rowCount * colCount;
      
      // Calculate sum and average for numeric values
      double sum = 0;
      int numericCount = 0;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          final val = _data[r][_columns[c]] ?? '';
          final num = double.tryParse(val.replaceAll(',', ''));
          if (num != null) {
            sum += num;
            numericCount++;
          }
        }
      }
      
      info = 'Count: $cellCount';
      if (numericCount > 0) {
        final avg = sum / numericCount;
        info += '  |  Sum: ${sum.toStringAsFixed(2)}  |  Average: ${avg.toStringAsFixed(2)}';
      }
    } else if (_selectedRow != null && _selectedCol != null) {
      info = 'Cell: ${_getCellReference(_selectedRow!, _selectedCol!)}';
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F3F3),
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              info,
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[700],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_data.isNotEmpty)
            Text(
              '${_data.length} rows × ${_columns.length} cols',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey[500],
              ),
            ),
        ],
      ),
    );
  }
}
