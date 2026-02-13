import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
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

  SheetModel({
    required this.id,
    required this.name,
    this.columns = const [],
    this.rows = const [],
    this.createdAt,
    this.updatedAt,
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
    );
  }
}

class SheetScreen extends StatefulWidget {
  const SheetScreen({super.key});

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  List<SheetModel> _sheets = [];
  SheetModel? _currentSheet;
  bool _isLoading = true;
  String? _error;
  
  // Spreadsheet state
  List<String> _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  List<Map<String, String>> _data = [];
  int? _editingRow;
  int? _editingCol;
  final _editController = TextEditingController();
  final _focusNode = FocusNode();
  int? _selectedRow;
  int? _selectedCol;
  
  // Scroll controllers for synchronized scrolling
  final _horizontalScrollController = ScrollController();
  final _verticalScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _initializeSheet();
    _loadSheets();
  }

  void _initializeSheet() {
    // Initialize with 100 empty rows
    _data = List.generate(100, (index) {
      final row = <String, String>{};
      for (var col in _columns) {
        row[col] = '';
      }
      return row;
    });
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
          _columns = sheet.columns;
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
        }
        _isLoading = false;
      });
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
      final response = await ApiService.createSheet(name, _columns);
      final sheet = SheetModel.fromJson(response['sheet']);
      setState(() {
        _sheets.insert(0, sheet);
        _currentSheet = sheet;
        _initializeSheet();
        _isLoading = false;
      });
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

  Future<String?> _showNameDialog(String title, String hint) async {
    final controller = TextEditingController();
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
    });
  }

  void _startEditing(int row, int col) {
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
      });
    }
  }

  void _cancelEdit() {
    setState(() {
      _editingRow = null;
      _editingCol = null;
    });
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;
    
    if (_editingRow != null && _editingCol != null) {
      // In editing mode
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        _saveEdit();
        // Move to next row
        if (_editingRow! < _data.length - 1) {
          _startEditing(_editingRow! + 1, _editingCol!);
        }
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        _saveEdit();
        // Move to next column
        if (_editingCol! < _columns.length - 1) {
          _startEditing(_editingRow!, _editingCol! + 1);
        }
      }
    } else if (_selectedRow != null && _selectedCol != null) {
      // In selection mode
      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.f2) {
        _startEditing(_selectedRow!, _selectedCol!);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp && _selectedRow! > 0) {
        setState(() => _selectedRow = _selectedRow! - 1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown && _selectedRow! < _data.length - 1) {
        setState(() => _selectedRow = _selectedRow! + 1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft && _selectedCol! > 0) {
        setState(() => _selectedCol = _selectedCol! - 1);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight && _selectedCol! < _columns.length - 1) {
        setState(() => _selectedCol = _selectedCol! + 1);
      } else if (event.logicalKey == LogicalKeyboardKey.delete) {
        setState(() {
          _data[_selectedRow!][_columns[_selectedCol!]] = '';
        });
      }
    }
  }

  @override
  void dispose() {
    _editController.dispose();
    _focusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<AuthProvider>(
        builder: (context, auth, _) {
          // Check role permissions
          final role = auth.user?.role ?? '';
          if (role != 'admin' && role != 'manager' && role != 'editor') {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Access Denied',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text('You do not have permission to access the Sheet module.'),
                ],
              ),
            );
          }

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
                    // Spreadsheet
                    Expanded(
                      child: _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : _buildSpreadsheet(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey[100],
      child: Row(
        children: [
          Text(
            _currentSheet?.name ?? 'Sheet',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _createNewSheet,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('New Sheet'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _addColumn,
            icon: const Icon(Icons.view_column, size: 18),
            label: const Text('Add Column'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: _addRow,
            icon: const Icon(Icons.table_rows, size: 18),
            label: const Text('Add Row'),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _saveSheet,
            icon: const Icon(Icons.save, size: 18),
            label: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildSheetList() {
    return Container(
      width: 200,
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Sheets',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _sheets.isEmpty
                ? Center(
                    child: Text(
                      'No sheets yet',
                      style: TextStyle(color: Colors.grey[500]),
                    ),
                  )
                : ListView.builder(
                    itemCount: _sheets.length,
                    itemBuilder: (context, index) {
                      final sheet = _sheets[index];
                      final isSelected = _currentSheet?.id == sheet.id;
                      return ListTile(
                        dense: true,
                        selected: isSelected,
                        selectedTileColor: Colors.blue[50],
                        leading: Icon(
                          Icons.grid_on,
                          size: 20,
                          color: isSelected ? Colors.blue : Colors.grey,
                        ),
                        title: Text(
                          sheet.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => _loadSheetData(sheet.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpreadsheet() {
    return KeyboardListener(
      focusNode: FocusNode(),
      onKeyEvent: _handleKeyEvent,
      child: GestureDetector(
        onTap: () {
          if (_editingRow != null) {
            _saveEdit();
          }
        },
        child: SingleChildScrollView(
          controller: _verticalScrollController,
          child: SingleChildScrollView(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
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
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    const cellWidth = 120.0;
    const rowNumWidth = 50.0;

    return Container(
      color: Colors.grey[200],
      child: Row(
        children: [
          // Row number header
          Container(
            width: rowNumWidth,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[400]!),
              color: Colors.grey[300],
            ),
            child: const Text(''),
          ),
          // Column headers
          ..._columns.asMap().entries.map((entry) {
            return Container(
              width: cellWidth,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[400]!),
                color: _selectedCol == entry.key ? Colors.blue[100] : Colors.grey[200],
              ),
              child: Text(
                entry.value,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildDataRow(int rowIndex) {
    const cellWidth = 120.0;
    const rowNumWidth = 50.0;
    const cellHeight = 28.0;

    return Row(
      children: [
        // Row number
        Container(
          width: rowNumWidth,
          height: cellHeight,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey[400]!),
            color: _selectedRow == rowIndex ? Colors.blue[100] : Colors.grey[200],
          ),
          child: Text(
            '${rowIndex + 1}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ),
        // Data cells
        ..._columns.asMap().entries.map((entry) {
          final colIndex = entry.key;
          final colName = entry.value;
          final isEditing = _editingRow == rowIndex && _editingCol == colIndex;
          final isSelected = _selectedRow == rowIndex && _selectedCol == colIndex;
          final value = _data[rowIndex][colName] ?? '';

          return GestureDetector(
            onTap: () {
              if (_editingRow != null) {
                _saveEdit();
              }
              setState(() {
                _selectedRow = rowIndex;
                _selectedCol = colIndex;
              });
            },
            onDoubleTap: () => _startEditing(rowIndex, colIndex),
            child: Container(
              width: cellWidth,
              height: cellHeight,
              decoration: BoxDecoration(
                border: Border.all(
                  color: isSelected ? Colors.blue : Colors.grey[300]!,
                  width: isSelected ? 2 : 1,
                ),
                color: isSelected ? Colors.blue[50] : Colors.white,
              ),
              child: isEditing
                  ? TextField(
                      controller: _editController,
                      focusNode: _focusNode,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onSubmitted: (_) {
                        _saveEdit();
                        if (rowIndex < _data.length - 1) {
                          _startEditing(rowIndex + 1, colIndex);
                        }
                      },
                      onEditingComplete: _saveEdit,
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        value,
                        style: const TextStyle(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
            ),
          );
        }),
      ],
    );
  }
}
