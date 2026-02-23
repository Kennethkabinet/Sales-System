import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:data_table_2/data_table_2.dart';
import '../providers/data_provider.dart';
import '../providers/auth_provider.dart';
import '../models/file.dart';

class TableViewScreen extends StatefulWidget {
  final FileModel file;

  const TableViewScreen({super.key, required this.file});

  @override
  State<TableViewScreen> createState() => _TableViewScreenState();
}

class _TableViewScreenState extends State<TableViewScreen> {
  int? _editingRow;
  String? _editingColumn;
  final _editController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userId = context.read<AuthProvider>().user?.id.toString() ?? '';
      context.read<DataProvider>().loadFileData(widget.file.id, userId);
    });
  }

  @override
  void dispose() {
    _editController.dispose();
    _focusNode.dispose();
    // Leave file when screen is disposed
    final provider = context.read<DataProvider>();
    if (provider.currentFileId != null) {
      provider.leaveFile();
    }
    super.dispose();
  }

  void _startEditing(int rowIndex, String column, dynamic value) {
    final data = context.read<DataProvider>();
    final row = data.fileData[rowIndex];
    final rowId = row['id']?.toString() ?? rowIndex.toString();

    // Check if row is locked by someone else
    if (data.lockedRows.containsKey(rowId) &&
        data.lockedRows[rowId] !=
            context.read<AuthProvider>().user?.id.toString()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('This row is being edited by another user')),
      );
      return;
    }

    setState(() {
      _editingRow = rowIndex;
      _editingColumn = column;
      _editController.text = value?.toString() ?? '';
    });

    // Lock the row
    data.lockRow(rowId);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _saveEdit() {
    if (_editingRow == null || _editingColumn == null) return;

    final data = context.read<DataProvider>();
    final row = Map<String, dynamic>.from(data.fileData[_editingRow!]);
    final rowId = row['id']?.toString() ?? _editingRow.toString();

    row[_editingColumn!] = _editController.text;
    data.updateRow(rowId, row);
    data.unlockRow(rowId);

    setState(() {
      _editingRow = null;
      _editingColumn = null;
    });
  }

  void _cancelEdit() {
    if (_editingRow == null) return;

    final data = context.read<DataProvider>();
    final rowId =
        data.fileData[_editingRow!]['id']?.toString() ?? _editingRow.toString();
    data.unlockRow(rowId);

    setState(() {
      _editingRow = null;
      _editingColumn = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.file.name),
        actions: [
          // Active users indicator
          Consumer<DataProvider>(
            builder: (context, data, _) {
              if (data.activeUsers.isEmpty) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    const Icon(Icons.people, size: 20),
                    const SizedBox(width: 4),
                    Text('${data.activeUsers.length} online'),
                    const SizedBox(width: 8),
                    ...data.activeUsers.take(3).map((user) => Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Tooltip(
                            message: user.name,
                            child: CircleAvatar(
                              radius: 14,
                              backgroundColor: _getUserColor(user.id),
                              child: Text(
                                user.name.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                    fontSize: 12, color: Colors.white),
                              ),
                            ),
                          ),
                        )),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Add Row',
            onPressed: _addRow,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Export',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Export feature coming soon')),
              );
            },
          ),
        ],
      ),
      body: Consumer<DataProvider>(
        builder: (context, data, _) {
          if (data.isLoading && data.fileData.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (data.fileData.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.table_chart, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No data yet',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add),
                    label: const Text('Add First Row'),
                  ),
                ],
              ),
            );
          }

          // Get columns from first row
          final columns = data.fileColumns.isNotEmpty
              ? data.fileColumns
              : data.fileData.first.keys.where((k) => k != 'id').toList();

          return Column(
            children: [
              // Locked rows indicator
              if (data.lockedRows.isNotEmpty)
                Container(
                  color: Colors.orange[50],
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.lock, size: 16, color: Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        '${data.lockedRows.length} row(s) being edited',
                        style: const TextStyle(color: Colors.orange),
                      ),
                    ],
                  ),
                ),

              // Data table
              Expanded(
                child: DataTable2(
                  columnSpacing: 12,
                  horizontalMargin: 12,
                  minWidth: columns.length * 150.0,
                  headingRowColor: WidgetStateProperty.all(Colors.grey[100]),
                  columns: [
                    const DataColumn2(label: Text('#'), fixedWidth: 50),
                    ...columns.map((col) => DataColumn2(
                          label: Text(
                            col.toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        )),
                    const DataColumn2(label: Text('Actions'), fixedWidth: 80),
                  ],
                  rows: data.fileData.asMap().entries.map((entry) {
                    final index = entry.key;
                    final row = entry.value;
                    final rowId = row['id']?.toString() ?? index.toString();
                    final isLocked = data.lockedRows.containsKey(rowId);
                    final isLockedByMe = isLocked &&
                        data.lockedRows[rowId] ==
                            context.read<AuthProvider>().user?.id.toString();
                    final isLockedByOther = isLocked && !isLockedByMe;

                    return DataRow2(
                      color: isLockedByOther
                          ? WidgetStateProperty.all(Colors.orange[50])
                          : isLockedByMe
                              ? WidgetStateProperty.all(Colors.blue[50])
                              : null,
                      cells: [
                        DataCell(
                          Row(
                            children: [
                              Text('${index + 1}'),
                              if (isLocked) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.lock,
                                  size: 12,
                                  color: isLockedByOther
                                      ? Colors.orange
                                      : Colors.blue,
                                ),
                              ],
                            ],
                          ),
                        ),
                        ...columns.map((col) {
                          final value = row[col];
                          final isEditing =
                              _editingRow == index && _editingColumn == col;

                          if (isEditing) {
                            return DataCell(
                              TextField(
                                controller: _editController,
                                focusNode: _focusNode,
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 8,
                                  ),
                                  border: OutlineInputBorder(),
                                ),
                                onSubmitted: (_) => _saveEdit(),
                                onEditingComplete: _saveEdit,
                              ),
                            );
                          }

                          return DataCell(
                            Text(value?.toString() ?? ''),
                            onTap: isLockedByOther
                                ? null
                                : () =>
                                    _startEditing(index, col.toString(), value),
                          );
                        }),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_editingRow == index) ...[
                                IconButton(
                                  icon: const Icon(Icons.check, size: 18),
                                  color: Colors.green,
                                  onPressed: _saveEdit,
                                  tooltip: 'Save',
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  color: Colors.red,
                                  onPressed: _cancelEdit,
                                  tooltip: 'Cancel',
                                ),
                              ] else ...[
                                IconButton(
                                  icon: const Icon(Icons.delete, size: 18),
                                  color: Colors.red,
                                  onPressed: isLockedByOther
                                      ? null
                                      : () => _deleteRow(rowId),
                                  tooltip: 'Delete',
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addRow() async {
    final data = context.read<DataProvider>();
    final columns = data.fileColumns.isNotEmpty
        ? data.fileColumns
        : (data.fileData.isNotEmpty
            ? data.fileData.first.keys.where((k) => k != 'id').toList()
            : ['Column1', 'Column2', 'Column3']);

    final newRow = <String, dynamic>{};
    for (final col in columns) {
      newRow[col.toString()] = '';
    }

    await data.addRow(newRow);
  }

  Future<void> _deleteRow(String rowId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Row'),
        content: const Text('Are you sure you want to delete this row?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await context.read<DataProvider>().deleteRow(rowId);
    }
  }

  Color _getUserColor(String id) {
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
    ];
    return colors[id.hashCode.abs() % colors.length];
  }
}
