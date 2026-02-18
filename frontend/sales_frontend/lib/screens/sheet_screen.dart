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
  String? _lastShownLockUser; // Track which lock user we already notified about
  
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
  
  // Ribbon toolbar state
  String _selectedRibbonTab = 'Edit';

  // Cell formatting state – key is "row,col"
  final Map<String, Set<String>> _cellFormats = {}; // e.g. {'bold','italic','underline'}
  final Map<String, double> _cellFontSizes = {};    // custom font size
  final Map<String, TextAlign> _cellAlignments = {}; // custom alignment
  double _currentFontSize = 13.0;
  static const List<double> _fontSizeOptions = [10, 11, 12, 13, 14, 16, 18, 20, 24, 28, 32];
  
  // Timer for periodic status updates
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _initializeSheet();
    _loadSheets();
    
    // Set up periodic status refresh (every 10 seconds)
    _statusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
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
      
      final wasLockedByOther = _lockedByUser;
      setState(() {
        _isLocked = status['is_locked'] ?? false;
        _lockedByUser = status['locked_by'];
        _activeEditors = (status['active_editors'] as List<dynamic>?)
            ?.map((e) => e['username'] as String)
            .toList() ?? [];
      });

      // Show one-time snackbar when a different user locks the sheet
      if (mounted && _isLocked && _lockedByUser != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUsername = authProvider.user?.username ?? '';
        if (_lockedByUser != currentUsername && _lastShownLockUser != _lockedByUser) {
          _lastShownLockUser = _lockedByUser;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_lockedByUser is currently editing this sheet'),
              backgroundColor: Colors.orange[700],
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
      // Reset when lock is released
      if (!_isLocked) {
        _lastShownLockUser = null;
      }
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

    // Check if sheet is locked by another user
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (_isLocked && _lockedByUser != null && _lockedByUser != authProvider.user?.username && authProvider.user?.role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Cannot save: $_lockedByUser is currently editing this sheet'),
          backgroundColor: Colors.orange[700],
        ),
      );
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

  Future<void> _renameSheet(SheetModel sheet) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';

    // Check permissions - only admin and editor can rename
    if (userRole != 'admin' && userRole != 'editor') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to rename sheets'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final newName = await _showNameDialog(
      'Rename Sheet',
      'Enter new sheet name',
      initialValue: sheet.name,
    );

    if (newName == null || newName.trim().isEmpty || newName.trim() == sheet.name) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.renameSheet(sheet.id, newName.trim());

      // Update sheet name in the local list
      final index = _sheets.indexWhere((s) => s.id == sheet.id);
      if (index != -1) {
        _sheets[index] = SheetModel(
          id: sheet.id,
          name: newName.trim(),
          columns: sheet.columns,
          rows: sheet.rows,
          createdAt: sheet.createdAt,
          updatedAt: DateTime.now(),
          shownToViewers: sheet.shownToViewers,
          lockedBy: sheet.lockedBy,
          lockedByName: sheet.lockedByName,
          lockedAt: sheet.lockedAt,
          editingUserId: sheet.editingUserId,
          editingUserName: sheet.editingUserName,
        );
      }

      // Update current sheet if it's the one being renamed
      if (_currentSheet?.id == sheet.id) {
        _currentSheet = _sheets[index];
      }

      setState(() => _isLoading = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sheet renamed to "$newName"'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to rename sheet: $e'), backgroundColor: Colors.red),
        );
      }
    }
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
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final role = authProvider.user?.role ?? '';
    if (role == 'viewer') return;
    
    // Prevent editing if sheet is locked by another user
    if (_isLocked && _lockedByUser != null && _lockedByUser != authProvider.user?.username) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_lockedByUser is currently editing this sheet'),
          backgroundColor: Colors.orange[700],
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    
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

  /// Check if current user can edit the sheet (not locked by another user)
  bool _canEditSheet() {
    if (widget.readOnly) return false;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final role = authProvider.user?.role ?? '';
    if (role == 'viewer') return false;
    if (_isLocked && _lockedByUser != null && _lockedByUser != authProvider.user?.username && role != 'admin') {
      return false;
    }
    return true;
  }

  /// Clear selection of all selected cells (Delete key)
  void _clearSelectedCells() {
    if (!_canEditSheet()) return;
    
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

  // ─── Theme colors (match dashboard) ───
  static const Color _kSidebarBg = Color(0xFFCD5C5C);
  static const Color _kContentBg = Color(0xFFFDF5F0);
  static const Color _kNavy = Color(0xFF1E3A6E);
  static const Color _kBlue = Color(0xFF3B5998);

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final role = auth.user?.role ?? '';
        final isViewer = role == 'viewer';

        // If a sheet is opened, show the spreadsheet editor
        if (_currentSheet != null) {
          return Scaffold(
            backgroundColor: _kContentBg,
            body: Column(
              children: [
                // ── Red header bar ──
                _buildRedHeader(),
                // ── Sheet name + Save bar ──
                _buildSheetNameBar(),
                // ── Ribbon toolbar ──
                _buildRibbonToolbar(),
                // ── Formula bar ──
                _buildFormulaBar(),
                // ── Status bar for lock info ──
                if (_currentSheet != null) _buildStatusBar(),
                // ── Spreadsheet grid ──
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _buildSpreadsheetGrid2(),
                ),
                // ── Selection info bar ──
                _buildSelectionInfoBar(),
                // ── Sheet tabs at bottom ──
                _buildSheetTabs(),
              ],
            ),
          );
        }

        // Otherwise show the Work Sheets landing page
        return Scaffold(
          backgroundColor: _kContentBg,
          body: _isLoading && _sheets.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : _buildSheetListView(auth, isViewer),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Work Sheets Landing View (matches screenshot)
  // ═══════════════════════════════════════════════════════
  Widget _buildSheetListView(AuthProvider auth, bool isViewer) {
    // Sort sheets by updated date for "recent"
    final sortedSheets = List<SheetModel>.from(_sheets)
      ..sort((a, b) {
        final aDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
        final bDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });
    final recentSheets = sortedSheets.take(5).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title ──
          const Text(
            'WORK SHEETS',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: _kNavy,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),

          // ── Action buttons row ──
          if (!isViewer)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _buildOutlinedBtn(
                  icon: Icons.create_new_folder_outlined,
                  label: 'New Folder',
                  onPressed: () {}, // placeholder
                ),
                const SizedBox(width: 10),
                _buildOutlinedBtn(
                  icon: Icons.upload_file,
                  label: 'Import Excel',
                  onPressed: _importSheet,
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _createNewSheet,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New Sheet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kNavy,
                    foregroundColor: Colors.white,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 20),

          // ── Recent Sheets ──
          if (recentSheets.isNotEmpty) ...[
            const Text(
              'Recent Sheets',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: _kSidebarBg,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 125,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: recentSheets.length,
                separatorBuilder: (_, __) => const SizedBox(width: 14),
                itemBuilder: (context, index) {
                  final sheet = recentSheets[index];
                  return _buildRecentCard(sheet);
                },
              ),
            ),
            const SizedBox(height: 28),
          ],

          // ── All Sheets table ──
          const Text(
            'All Sheets',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: _kBlue,
            ),
          ),
          const SizedBox(height: 12),

          if (_sheets.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 48),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                children: [
                  Icon(Icons.description_outlined,
                      size: 48, color: Colors.grey[300]),
                  const SizedBox(height: 12),
                  Text(
                    isViewer
                        ? 'No sheets shared with you yet'
                        : 'No sheets yet — create one!',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
                  ),
                ],
              ),
            )
          else
            _buildAllSheetsTable(auth),
        ],
      ),
    );
  }

  // ── Recent sheet card ──
  Widget _buildRecentCard(SheetModel sheet) {
    final timeAgo = _timeAgo(sheet.updatedAt ?? sheet.createdAt);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _loadSheetData(sheet.id),
      child: Container(
        width: 160,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.green[600],
                borderRadius: BorderRadius.circular(6),
              ),
              child:
                  const Icon(Icons.description, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 10),
            Text(
              sheet.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              timeAgo,
              style: TextStyle(fontSize: 11, color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  // ── All Sheets data table ──
  Widget _buildAllSheetsTable(AuthProvider auth) {
    final role = auth.user?.role ?? '';
    final canManage = role == 'admin' || role == 'editor' || role == 'manager';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(Colors.grey.shade50),
        headingTextStyle: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: Colors.grey[700],
        ),
        dataRowMinHeight: 48,
        dataRowMaxHeight: 56,
        columnSpacing: 24,
        columns: const [
          DataColumn(label: Text('Name')),
          DataColumn(label: Text('Owner')),
          DataColumn(label: Text('Rows'), numeric: true),
          DataColumn(label: Text('Created')),
          DataColumn(label: Text('Last Modified')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _sheets.map((sheet) {
          return DataRow(
            cells: [
              // Name
              DataCell(
                InkWell(
                  onTap: () => _loadSheetData(sheet.id),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(Icons.description,
                            color: Colors.white, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sheet.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            '${sheet.rows.length} rows',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey[400]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Owner
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: Colors.grey[300],
                    child: Icon(Icons.person, size: 14, color: Colors.grey[600]),
                  ),
                  const SizedBox(width: 6),
                  Text('admin', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              )),
              // Rows
              DataCell(Text(
                '${sheet.rows.length}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              )),
              // Created
              DataCell(Text(
                _formatDate(sheet.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              )),
              // Last Modified
              DataCell(Text(
                _formatDate(sheet.updatedAt ?? sheet.createdAt),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              )),
              // Actions
              DataCell(
                canManage
                    ? PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert,
                            size: 18, color: Colors.grey[500]),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          if (value == 'open') _loadSheetData(sheet.id);
                          if (value == 'rename') _renameSheet(sheet);
                          if (value == 'delete') _confirmDeleteSheet(sheet);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                              value: 'open', child: Text('Open')),
                          const PopupMenuItem(
                              value: 'rename', child: Text('Rename')),
                          if (role == 'admin' || role == 'manager')
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete',
                                  style: TextStyle(color: Colors.red)),
                            ),
                        ],
                      )
                    : const SizedBox(),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }

  // ── Outlined action button ──
  Widget _buildOutlinedBtn({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: _kNavy),
      label: Text(label, style: const TextStyle(color: _kNavy, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: _kNavy),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  // ── Date formatter ──
  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return '${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return _formatDate(dt);
  }

  // ═══════════════════════════════════════════════════════
  //  Red Header Bar
  // ═══════════════════════════════════════════════════════
  Widget _buildRedHeader() {
    return Container(
      height: 48,
      color: _kSidebarBg,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 22),
            tooltip: 'Back to Work Sheets',
            onPressed: () {
              setState(() {
                _currentSheet = null;
                _selectedRow = null;
                _selectedCol = null;
                _selectionEndRow = null;
                _selectionEndCol = null;
                _editingRow = null;
                _editingCol = null;
              });
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'WORK SHEETS',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Sheet Name + Save Bar
  // ═══════════════════════════════════════════════════════
  Widget _buildSheetNameBar() {
    final isViewer = (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '') == 'viewer';
    return Container(
      height: 40,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.description, size: 18, color: Colors.green[700]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _currentSheet?.name ?? 'Untitled',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!widget.readOnly && !isViewer)
            ElevatedButton.icon(
              onPressed: _canEditSheet() ? _saveSheet : null,
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Save', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _canEditSheet() ? _kBlue : Colors.grey[400],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                elevation: 0,
                minimumSize: const Size(0, 30),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Ribbon Toolbar (File / Edit / Structure tabs)
  // ═══════════════════════════════════════════════════════
  Widget _buildRibbonToolbar() {
    final isViewer = (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '') == 'viewer';
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[50],
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Tab headers
          Container(
            height: 32,
            color: Colors.white,
            child: Row(
              children: [
                _buildRibbonTab('File'),
                _buildRibbonTab('Edit'),
                _buildRibbonTab('Structure'),
              ],
            ),
          ),
          // Tab content
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: Colors.white,
            child: _buildRibbonContent(isViewer),
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonTab(String label) {
    final isSelected = _selectedRibbonTab == label;
    return GestureDetector(
      onTap: () => setState(() => _selectedRibbonTab = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isSelected ? _kSidebarBg : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? _kSidebarBg : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildRibbonContent(bool isViewer) {
    switch (_selectedRibbonTab) {
      case 'File':
        return _buildFileRibbon(isViewer);
      case 'Edit':
        return _buildEditRibbon(isViewer);
      case 'Structure':
        return _buildStructureRibbon(isViewer);
      default:
        return const SizedBox();
    }
  }

  // ── File ribbon: Import, Export, New ──
  Widget _buildFileRibbon(bool isViewer) {
    return Row(
      children: [
        if (!isViewer && !widget.readOnly) ...[
          _buildRibbonButton(Icons.upload_file, 'Import', _canEditSheet() ? _importSheet : null),
          const SizedBox(width: 6),
        ],
        _buildRibbonButton(Icons.download, 'Export', _showExportMenu),
        if (!isViewer && !widget.readOnly) ...[
          const SizedBox(width: 6),
          _buildRibbonButton(Icons.add_circle_outline, 'New', _createNewSheet),
        ],
      ],
    );
  }

  // ── Edit ribbon: B, I, U, font, align, Edit/Lock, Show ──
  Widget _buildEditRibbon(bool isViewer) {
    if (isViewer || widget.readOnly) {
      return Row(
        children: [
          Text('View-only mode', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';
    final canCollab = userRole == 'admin' || userRole == 'editor' || userRole == 'user';
    final isLockedByMe = _isLocked && _lockedByUser != null &&
        (_lockedByUser == authProvider.user?.username || userRole == 'admin');

    // Current selection formatting state
    final key = (_selectedRow != null && _selectedCol != null)
        ? '${_selectedRow!},${_selectedCol!}'
        : null;
    final formats = key != null ? (_cellFormats[key] ?? <String>{}) : <String>{};
    final isBold = formats.contains('bold');
    final isItalic = formats.contains('italic');
    final isUnderline = formats.contains('underline');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // ── Text formatting icons ──
          _buildFormatToggle(Icons.format_bold, 'Bold', isBold, () => _toggleFormat('bold')),
          _buildFormatToggle(Icons.format_italic, 'Italic', isItalic, () => _toggleFormat('italic')),
          _buildFormatToggle(Icons.format_underlined, 'Underline', isUnderline, () => _toggleFormat('underline')),
          _buildRibbonDivider(),
          _buildFontSizeButton(),
          const SizedBox(width: 4),
          _buildAlignmentButton(),
          _buildRibbonDivider(),

          // ── Edit button ──
          if (canCollab)
            _buildRibbonButton(
              Icons.edit,
              _isLocked && isLockedByMe ? 'Editing' : 'Edit',
              _isLocked
                  ? (isLockedByMe ? null : null)
                  : _lockSheet,
            ),
          if (canCollab) const SizedBox(width: 6),

          // ── Lock / Unlock button ──
          if (canCollab)
            _buildRibbonButton(
              _isLocked ? Icons.lock : Icons.lock_outline,
              _isLocked ? 'Unlock' : 'Lock',
              _isLocked
                  ? (isLockedByMe ? _unlockSheet : null)
                  : _lockSheet,
            ),
          if (canCollab) const SizedBox(width: 6),

          // ── Show / Hide button (admin only) ──
          if (userRole == 'admin' && _currentSheet != null)
            _buildRibbonButton(
              _currentSheet!.shownToViewers ? Icons.visibility : Icons.visibility_off,
              _currentSheet!.shownToViewers ? 'Hide' : 'Show',
              () => _toggleSheetVisibility(
                _currentSheet!.id,
                !_currentSheet!.shownToViewers,
              ),
            ),
        ],
      ),
    );
  }

  // ── Formatting helpers ──
  String _cellKey(int row, int col) => '$row,$col';

  void _toggleFormat(String fmt) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          final k = _cellKey(r, c);
          _cellFormats.putIfAbsent(k, () => <String>{});
          if (_cellFormats[k]!.contains(fmt)) {
            _cellFormats[k]!.remove(fmt);
          } else {
            _cellFormats[k]!.add(fmt);
          }
        }
      }
    });
  }

  void _setFontSize(double size) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      _currentFontSize = size;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellFontSizes[_cellKey(r, c)] = size;
        }
      }
    });
  }

  void _setAlignment(TextAlign align) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellAlignments[_cellKey(r, c)] = align;
        }
      }
    });
  }

  Widget _buildFormatToggle(IconData icon, String tooltip, bool active, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? _kNavy.withOpacity(0.12) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: active ? Border.all(color: _kNavy.withOpacity(0.3)) : null,
          ),
          child: Icon(icon, size: 18, color: _kNavy),
        ),
      ),
    );
  }

  Widget _buildFontSizeButton() {
    return PopupMenuButton<double>(
      tooltip: 'Font Size',
      onSelected: _setFontSize,
      offset: const Offset(0, 36),
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.text_fields, size: 16, color: _kNavy),
            const SizedBox(width: 4),
            Text(
              '${_currentFontSize.toInt()}',
              style: TextStyle(fontSize: 12, color: _kNavy, fontWeight: FontWeight.w500),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
      itemBuilder: (_) => _fontSizeOptions.map((s) {
        return PopupMenuItem<double>(
          value: s,
          child: Text('${s.toInt()} px', style: TextStyle(
            fontSize: s.clamp(11, 18),
            fontWeight: s == _currentFontSize ? FontWeight.bold : FontWeight.normal,
          )),
        );
      }).toList(),
    );
  }

  Widget _buildAlignmentButton() {
    // Determine current alignment icon
    IconData alignIcon = Icons.format_align_left;
    if (_selectedRow != null && _selectedCol != null) {
      final a = _cellAlignments[_cellKey(_selectedRow!, _selectedCol!)];
      if (a == TextAlign.center) alignIcon = Icons.format_align_center;
      if (a == TextAlign.right) alignIcon = Icons.format_align_right;
    }
    return PopupMenuButton<TextAlign>(
      tooltip: 'Alignment',
      onSelected: _setAlignment,
      offset: const Offset(0, 36),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(alignIcon, size: 18, color: _kNavy),
      ),
      itemBuilder: (_) => [
        const PopupMenuItem(value: TextAlign.left, child: Row(children: [
          Icon(Icons.format_align_left, size: 18), SizedBox(width: 8), Text('Left'),
        ])),
        const PopupMenuItem(value: TextAlign.center, child: Row(children: [
          Icon(Icons.format_align_center, size: 18), SizedBox(width: 8), Text('Center'),
        ])),
        const PopupMenuItem(value: TextAlign.right, child: Row(children: [
          Icon(Icons.format_align_right, size: 18), SizedBox(width: 8), Text('Right'),
        ])),
      ],
    );
  }

  // ── Structure ribbon: +Column, +Row, -Column, -Row ──
  Widget _buildStructureRibbon(bool isViewer) {
    if (isViewer || widget.readOnly) {
      return Row(
        children: [
          Text('View-only mode', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }
    return Row(
      children: [
        _buildRibbonButton(Icons.view_column_outlined, '+ Column', _canEditSheet() ? _addColumn : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.table_rows_outlined, '+ Row', _canEditSheet() ? _addRow : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.remove_circle_outline, '- Column', _canEditSheet() ? _deleteColumn : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.remove_circle_outline, '- Row', _canEditSheet() ? _deleteRow : null),
      ],
    );
  }

  // ── Ribbon sub-widgets ──
  Widget _buildRibbonButton(IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: enabled ? Colors.grey[300]! : Colors.grey[200]!),
            borderRadius: BorderRadius.circular(6),
            color: enabled ? Colors.white : Colors.grey[100],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: enabled ? _kNavy : Colors.grey[400]),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: enabled ? _kNavy : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRibbonDivider() {
    return Container(
      height: 24,
      width: 1,
      color: Colors.grey[300],
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  // (collaborative controls are now inlined in _buildEditRibbon)

  Widget _buildStatusBar() {
    if (_currentSheet == null) return const SizedBox();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUsername = authProvider.user?.username ?? '';
    final hasLock = _isLocked && _lockedByUser != null && _lockedByUser!.isNotEmpty;
    final isLockedByMe = hasLock && _lockedByUser == currentUsername;

    // Show editing indicator when locked by me
    if (isLockedByMe) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.green[50],
          border: Border(
            bottom: BorderSide(color: Colors.green[300]!, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.edit, size: 16, color: Colors.green[700]),
            const SizedBox(width: 8),
            Text(
              'You are editing this sheet (locked)',
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

    return const SizedBox();
  }

  // ═══════════════════════════════════════════════════════
  //  Spreadsheet Grid (new wrapper without internal formula bar)
  // ═══════════════════════════════════════════════════════
  Widget _buildSpreadsheetGrid2() {
    return Focus(
      focusNode: _spreadsheetFocusNode,
      onKeyEvent: (node, event) {
        _handleKeyEvent(event);
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
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Sheet Tabs at Bottom
  // ═══════════════════════════════════════════════════════
  Widget _buildSheetTabs() {
    // Build tab list from loaded sheets, highlighting current
    final visibleSheets = _sheets.take(10).toList();
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(
          top: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Add sheet button
          if (!widget.readOnly && (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '') != 'viewer')
            InkWell(
              onTap: _createNewSheet,
              child: Container(
                width: 30,
                height: 34,
                alignment: Alignment.center,
                child: Icon(Icons.add, size: 16, color: Colors.grey[600]),
              ),
            ),
          Container(width: 1, height: 34, color: Colors.grey[300]),
          // Sheet tabs
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: visibleSheets.length,
              itemBuilder: (context, index) {
                final sheet = visibleSheets[index];
                final isActive = sheet.id == _currentSheet?.id;
                return GestureDetector(
                  onTap: () {
                    if (!isActive) _loadSheetData(sheet.id);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.transparent,
                      border: Border(
                        right: BorderSide(color: Colors.grey[300]!, width: 1),
                        top: isActive
                            ? const BorderSide(color: _kSidebarBg, width: 2)
                            : BorderSide.none,
                      ),
                    ),
                    child: Text(
                      sheet.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                        color: isActive ? _kNavy : Colors.grey[600],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
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
                    Builder(builder: (_) {
                      final ck = _cellKey(rowIndex, colIndex);
                      final fmts = _cellFormats[ck] ?? <String>{};
                      final fontSize = _cellFontSizes[ck] ?? 13.0;
                      final align = _cellAlignments[ck];
                      Alignment cellAlign;
                      if (align == TextAlign.center) {
                        cellAlign = Alignment.center;
                      } else if (align == TextAlign.right) {
                        cellAlign = Alignment.centerRight;
                      } else if (align == TextAlign.left) {
                        cellAlign = Alignment.centerLeft;
                      } else {
                        cellAlign = _isNumeric(value) ? Alignment.centerRight : Alignment.centerLeft;
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Align(
                          alignment: cellAlign,
                          child: Text(
                            value,
                            style: TextStyle(
                              fontSize: fontSize,
                              color: Colors.black87,
                              fontFamily: 'Segoe UI',
                              fontWeight: fmts.contains('bold') ? FontWeight.bold : FontWeight.normal,
                              fontStyle: fmts.contains('italic') ? FontStyle.italic : FontStyle.normal,
                              decoration: fmts.contains('underline') ? TextDecoration.underline : TextDecoration.none,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      );
                    }),
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
