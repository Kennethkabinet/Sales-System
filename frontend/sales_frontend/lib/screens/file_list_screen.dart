import 'package:flutter/material.dart';
import '../config/constants.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/data_provider.dart';
import '../models/file.dart';
import '../services/api_service.dart';
import 'table_view_screen.dart';
import 'dart:io';
import '../widgets/app_modal.dart';

class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  final Set<int> _selectedFileIds = {};

  static const List<String> _scenarioFolders = [
    'Inventory',
    'Suppliers',
    'Production',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadFiles();
    });
  }

  // ============== Dialogs ==============

  Future<String?> _showNameDialog(
      {String title = 'Name', String? initialValue}) async {
    final controller = TextEditingController(text: initialValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Enter name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          onSubmitted: (val) => Navigator.pop(context, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<int?> _showMoveToFolderDialog(DataProvider data) async {
    // Fetch root folders for the move dialog
    final result = await ApiService.getFiles(folderId: null);
    final folders = result.folders;

    if (!mounted) return null;
    return showDialog<int?>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.home),
                title: const Text('Root (Home)'),
                onTap: () => Navigator.pop(context, -1), // -1 means root
              ),
              const Divider(),
              if (folders.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('No folders available'),
                )
              else
                ...folders.map((f) => ListTile(
                      leading: const Icon(Icons.folder, color: Colors.amber),
                      title: Text(f.name),
                      onTap: () => Navigator.pop(context, f.id),
                    )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Future<void> _openOrCreateScenarioFolder(String folderName) async {
    final data = context.read<DataProvider>();
    await data.loadFiles(folderId: null);
    if (!mounted) return;

    FolderModel? folder;
    for (final f in data.folders) {
      if (f.name.trim().toLowerCase() == folderName.toLowerCase()) {
        folder = f;
        break;
      }
    }

    if (folder == null) {
      await ApiService.createFolder(folderName);
      await data.loadFiles(folderId: null);
      if (!mounted) return;
      for (final f in data.folders) {
        if (f.name.trim().toLowerCase() == folderName.toLowerCase()) {
          folder = f;
          break;
        }
      }
    }

    if (folder != null && mounted) {
      data.navigateToFolder(folder.id, folder.name);
    }
  }

  Future<void> _createMonthlyInventoryWorkspace() async {
    final now = DateTime.now();
    final yearController = TextEditingController(text: '${now.year}');
    final monthController = TextEditingController(text: '${now.month}');

    final values = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create Monthly Inventory Workspace'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: yearController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Year',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: monthController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Month (1-12)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final y = int.tryParse(yearController.text.trim());
              final m = int.tryParse(monthController.text.trim());
              if (y == null || m == null) return;
              Navigator.pop(context, {'year': y, 'month': m});
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (values == null || !mounted) return;

    try {
      final response = await ApiService.createMonthlyInventoryWorkspace(
        year: values['year']!,
        month: values['month']!,
      );

      if (!mounted) return;
      final workspace = response['workspace'] as Map<String, dynamic>?;
      final inventoryYearFolder =
          workspace?['folders']?['inventory_year'] as Map<String, dynamic>?;
      final inventorySheet =
          workspace?['sheets']?['inventory'] as Map<String, dynamic>?;

      final data = context.read<DataProvider>();
      await data.loadFiles(folderId: null);

      if (inventoryYearFolder != null) {
        final inventoryYearFolderId = inventoryYearFolder['id'] as int?;
        final inventoryYearFolderName =
            (inventoryYearFolder['name'] ?? '').toString();
        if (inventoryYearFolderId != null &&
            inventoryYearFolderName.isNotEmpty &&
            mounted) {
          await _openOrCreateScenarioFolder('Inventory');
          data.navigateToFolder(inventoryYearFolderId, inventoryYearFolderName);
        }
      }

      final createdSheetName = (inventorySheet?['name'] ?? '').toString();

      if (mounted) {
        await AppModal.showText(
          context,
          title: 'Workspace created',
          message: createdSheetName.isEmpty
              ? 'Linked monthly sheets created successfully'
              : 'Linked monthly sheets created: $createdSheetName',
        );
      }
    } catch (e) {
      if (!mounted) return;
      await AppModal.showText(
        context,
        title: 'Create failed',
        message: 'Failed to create workspace: $e',
      );
    }
  }

  // ============== Bulk Actions ==============

  Future<void> _bulkDeleteFiles() async {
    if (_selectedFileIds.isEmpty) return;
    final count = _selectedFileIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Selected Files'),
        content: Text(
            'Permanently delete $count file${count > 1 ? 's' : ''}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final data = context.read<DataProvider>();
    for (final id in List<int>.from(_selectedFileIds)) {
      try {
        await data.deleteFile(id);
      } catch (_) {}
    }
    setState(() => _selectedFileIds.clear());
  }

  Future<void> _bulkMoveFiles() async {
    if (_selectedFileIds.isEmpty) return;
    final data = context.read<DataProvider>();
    final targetId = await _showMoveToFolderDialog(data);
    if (targetId == null || !mounted) return;
    final folderId = targetId == -1 ? null : targetId;
    for (final id in List<int>.from(_selectedFileIds)) {
      try {
        await data.moveFileToFolder(id, folderId: folderId);
      } catch (_) {}
    }
    setState(() => _selectedFileIds.clear());
    if (mounted) {
      await AppModal.showText(
        context,
        title: 'Move complete',
        message: 'Files moved successfully',
      );
    }
  }

  // ============== Actions ==============

  Future<void> _importFile() async {
    final dataProvider = context.read<DataProvider>();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

    if (result != null && result.files.single.path != null && mounted) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      final name = await _showNameDialog(title: 'Import File');
      if (name != null && name.isNotEmpty) {
        final success = await dataProvider.uploadFile(
          filePath,
          fileName,
          name,
        );

        if (mounted) {
          await AppModal.showText(
            context,
            title: success ? 'Upload complete' : 'Upload failed',
            message: success
                ? 'File "$fileName" uploaded successfully!'
                : 'Failed to upload file',
          );
        }
      }
    }
  }

  Future<void> _createNewFile() async {
    final name = await _showNameDialog(title: 'New File');
    if (name != null && name.isNotEmpty && mounted) {
      await context.read<DataProvider>().createFile(name);
    }
  }

  Future<void> _createNewFolder() async {
    final name = await _showNameDialog(title: 'New Folder');
    if (name != null && name.isNotEmpty && mounted) {
      final dataProvider = context.read<DataProvider>();
      final breadcrumbs = dataProvider.folderBreadcrumbs;
      final selectedParentId = breadcrumbs.isNotEmpty
          ? breadcrumbs.last['id'] as int?
          : dataProvider.currentFolderId;

      final success = await dataProvider.createFolder(
        name,
        parentId: selectedParentId,
      );
      if (mounted) {
        await AppModal.showText(
          context,
          title: success ? 'Folder created' : 'Create failed',
          message:
              success ? 'Folder "$name" created' : 'Failed to create folder',
        );
      }
    }
  }

  Future<void> _renameFile(FileModel file) async {
    final name =
        await _showNameDialog(title: 'Rename File', initialValue: file.name);
    if (name != null && name.isNotEmpty && mounted) {
      final success =
          await context.read<DataProvider>().renameFileItem(file.id, name);
      if (mounted) {
        await AppModal.showText(
          context,
          title: success ? 'Rename complete' : 'Rename failed',
          message:
              success ? 'File renamed to "$name"' : 'Failed to rename file',
        );
      }
    }
  }

  Future<void> _renameFolder(FolderModel folder) async {
    final name = await _showNameDialog(
        title: 'Rename Folder', initialValue: folder.name);
    if (name != null && name.isNotEmpty && mounted) {
      final success =
          await context.read<DataProvider>().renameFolder(folder.id, name);
      if (mounted) {
        await AppModal.showText(
          context,
          title: success ? 'Rename complete' : 'Rename failed',
          message:
              success ? 'Folder renamed to "$name"' : 'Failed to rename folder',
        );
      }
    }
  }

  Future<void> _moveFile(FileModel file) async {
    final data = context.read<DataProvider>();
    final targetId = await _showMoveToFolderDialog(data);
    if (targetId != null && mounted) {
      final folderId = targetId == -1 ? null : targetId;
      final success = await data.moveFileToFolder(file.id, folderId: folderId);
      if (mounted) {
        await AppModal.showText(
          context,
          title: success ? 'Move complete' : 'Move failed',
          message: success ? 'File moved successfully' : 'Failed to move file',
        );
      }
    }
  }

  Future<void> _downloadFile(FileModel file) async {
    try {
      final bytes = await ApiService.downloadFile(file.id);

      // Use file_picker to let user choose save location
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save File',
        fileName: '${file.name}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (outputPath != null) {
        final f = File(outputPath);
        await f.writeAsBytes(bytes);
        if (mounted) {
          await AppModal.showText(
            context,
            title: 'Download complete',
            message: 'Downloaded to: $outputPath',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        await AppModal.showText(
          context,
          title: 'Download failed',
          message: 'Download failed: $e',
        );
      }
    }
  }

  Future<void> _confirmDeleteFile(FileModel file) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file.name}"?'),
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
      await context.read<DataProvider>().deleteFile(file.id);
    }
  }

  Future<void> _confirmDeleteFolder(FolderModel folder) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
            'Are you sure you want to delete "${folder.name}"?\nFiles inside will be moved to root.'),
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
      await context.read<DataProvider>().deleteFolderItem(folder.id);
    }
  }

  // ============== Helpers ==============

  IconData _fileIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'xlsx':
      case 'xls':
        return Icons.table_chart;
      case 'csv':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _fileColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'xlsx':
      case 'xls':
        return AppColors.primaryRed;
      case 'csv':
        return AppColors.primaryBlue;
      default:
        return Colors.grey;
    }
  }

  String _fmtDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${date.month}/${date.day}/${date.year}';
  }

  Widget _buildFilesTable(List<FileModel> files) {
    final allSelected =
        files.isNotEmpty && files.every((f) => _selectedFileIds.contains(f.id));

    Widget hCell(String label, {TextAlign align = TextAlign.left}) => TableCell(
          verticalAlignment: TableCellVerticalAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(label,
                textAlign: align,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.black87)),
          ),
        );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(48), // checkbox
            1: FlexColumnWidth(3), // name
            2: FlexColumnWidth(1.2), // type
            3: FlexColumnWidth(1.5), // last modified
            4: FixedColumnWidth(100), // actions
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            // Header
            TableRow(
              decoration: BoxDecoration(color: Colors.grey.shade50),
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Checkbox(
                      value: allSelected,
                      tristate: _selectedFileIds.isNotEmpty && !allSelected,
                      onChanged: (_) => setState(() {
                        if (allSelected) {
                          _selectedFileIds.clear();
                        } else {
                          _selectedFileIds.addAll(files.map((f) => f.id));
                        }
                      }),
                    ),
                  ),
                ),
                hCell('Name'),
                hCell('Type'),
                hCell('Last Modified'),
                hCell('Actions', align: TextAlign.center),
              ],
            ),
            // Divider
            TableRow(
              children: List.generate(
                  5,
                  (_) =>
                      const TableCell(child: Divider(height: 1, thickness: 1))),
            ),
            // Data rows
            ...files.asMap().entries.map((entry) {
              final idx = entry.key;
              final file = entry.value;
              final isSelected = _selectedFileIds.contains(file.id);
              final rowBg = isSelected
                  ? AppColors.lightBlue
                  : idx.isEven
                      ? Colors.white
                      : const Color(0xFFF9FBF9);
              return TableRow(
                decoration: BoxDecoration(color: rowBg),
                children: [
                  // Checkbox
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selectedFileIds.add(file.id);
                          } else {
                            _selectedFileIds.remove(file.id);
                          }
                        }),
                      ),
                    ),
                  ),
                  // Name + row count below
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => TableViewScreen(file: file)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: _fileColor(file.type)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(5),
                              ),
                              child: Icon(_fileIcon(file.type),
                                  color: _fileColor(file.type), size: 16),
                            ),
                            const SizedBox(width: 10),
                            Flexible(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    '${file.rowCount ?? 0} rows',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.grey[400]),
                                  ),
                                ],
                              ),
                            ),
                            if (file.activeUsers > 0) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.people,
                                  size: 12, color: Colors.green),
                            ],
                            if (file.sourceSheetId != null) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF4FF),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Linked',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primaryBlue,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Tooltip(
                                message: 'Auto-saved from Sheet',
                                child: Icon(Icons.sync,
                                    size: 13, color: AppColors.primaryBlue),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Type
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(
                        (file.type ?? 'file').toUpperCase(),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  // Last Modified
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Text(
                        _fmtDate(file.updatedAt),
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    ),
                  ),
                  // Actions
                  TableCell(
                    verticalAlignment: TableCellVerticalAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert,
                                size: 18, color: Colors.grey[500]),
                            padding: EdgeInsets.zero,
                            onSelected: (value) {
                              switch (value) {
                                case 'rename':
                                  _renameFile(file);
                                  break;
                                case 'move':
                                  _moveFile(file);
                                  break;
                                case 'download':
                                  _downloadFile(file);
                                  break;
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'rename',
                                child: Row(children: [
                                  Icon(Icons.edit, size: 16),
                                  SizedBox(width: 8),
                                  Text('Rename')
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'move',
                                child: Row(children: [
                                  Icon(Icons.drive_file_move, size: 16),
                                  SizedBox(width: 8),
                                  Text('Move to Folder')
                                ]),
                              ),
                              PopupMenuItem(
                                value: 'download',
                                child: Row(children: [
                                  Icon(Icons.download, size: 16),
                                  SizedBox(width: 8),
                                  Text('Download')
                                ]),
                              ),
                            ],
                          ),
                          InkWell(
                            onTap: () => _confirmDeleteFile(file),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(Icons.delete_outline,
                                  size: 18, color: Colors.red[400]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  // ============== Build ==============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgLight,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Files',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _createMonthlyInventoryWorkspace,
                      icon: const Icon(Icons.account_tree_outlined),
                      label: const Text('Create Monthly Inventory Workspace'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _createNewFolder,
                      icon: const Icon(Icons.create_new_folder),
                      label: const Text('New Folder'),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _importFile,
                      icon: const Icon(Icons.upload_file),
                      label: const Text('Import Excel'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _createNewFile,
                      icon: const Icon(Icons.add),
                      label: const Text('New File'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Breadcrumbs
            Consumer<DataProvider>(
              builder: (context, data, _) {
                return _buildBreadcrumbs(data);
              },
            ),
            const SizedBox(height: 16),

            // Content
            Expanded(
              child: Consumer<DataProvider>(
                builder: (context, data, _) {
                  if (data.isLoading &&
                      data.files.isEmpty &&
                      data.folders.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (data.files.isEmpty && data.folders.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open,
                              size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            data.currentFolderId == null
                                ? 'No files yet'
                                : 'This folder is empty',
                            style: TextStyle(
                                fontSize: 18, color: Colors.grey[600]),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Create a new file, folder, or import an Excel spreadsheet',
                            style: TextStyle(color: Colors.grey[500]),
                          ),
                        ],
                      ),
                    );
                  }

                  final folders = data.folders;
                  final files = data.files;

                  return RefreshIndicator(
                    onRefresh: () =>
                        data.loadFiles(folderId: data.currentFolderId),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (data.currentFolderId == null) ...[
                            const Text('Scenario Folders',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: _scenarioFolders
                                  .map((name) => ActionChip(
                                        avatar: const Icon(Icons.folder,
                                            size: 16, color: Colors.amber),
                                        label: Text(name),
                                        onPressed: () =>
                                            _openOrCreateScenarioFolder(name),
                                      ))
                                  .toList(),
                            ),
                            const SizedBox(height: 18),
                          ],
                          // ── Folders grid ──
                          if (folders.isNotEmpty) ...[
                            const Text('Folders',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              children: folders
                                  .map((folder) => SizedBox(
                                        width: 200,
                                        height: 110,
                                        child: _FolderCard(
                                          folder: folder,
                                          onTap: () => data.navigateToFolder(
                                              folder.id, folder.name),
                                          onRename: () => _renameFolder(folder),
                                          onDelete: () =>
                                              _confirmDeleteFolder(folder),
                                        ),
                                      ))
                                  .toList(),
                            ),
                            const SizedBox(height: 24),
                          ],

                          // ── Files table ──
                          if (files.isNotEmpty) ...[
                            Row(
                              children: [
                                const Text('Files',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14)),
                                const Spacer(),
                                if (_selectedFileIds.isNotEmpty) ...[
                                  Text(
                                    '${_selectedFileIds.length} selected',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                        fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 10),
                                  OutlinedButton.icon(
                                    onPressed: _bulkMoveFiles,
                                    icon: const Icon(
                                        Icons.drive_file_move_outlined,
                                        size: 14),
                                    label: const Text('Move',
                                        style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.blueGrey,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  OutlinedButton.icon(
                                    onPressed: _bulkDeleteFiles,
                                    icon: const Icon(Icons.delete_outline,
                                        size: 14),
                                    label: const Text('Delete',
                                        style: TextStyle(fontSize: 12)),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  TextButton(
                                    onPressed: () => setState(
                                        () => _selectedFileIds.clear()),
                                    child: const Text('Clear',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 8),
                            _buildFilesTable(files),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreadcrumbs(DataProvider data) {
    final crumbs = data.folderBreadcrumbs;
    return Row(
      children: [
        InkWell(
          onTap: crumbs.isEmpty ? null : () => data.navigateToRoot(),
          child: Row(
            children: [
              Icon(Icons.home,
                  size: 18,
                  color: crumbs.isEmpty
                      ? Colors.grey[800]
                      : AppColors.primaryBlue),
              const SizedBox(width: 4),
              Text(
                'My Files',
                style: TextStyle(
                  color:
                      crumbs.isEmpty ? Colors.grey[800] : AppColors.primaryBlue,
                  fontWeight:
                      crumbs.isEmpty ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
        for (int i = 0; i < crumbs.length; i++) ...[
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ),
          InkWell(
            onTap: i == crumbs.length - 1
                ? null
                : () => data.navigateToBreadcrumb(i),
            child: Text(
              crumbs[i]['name'] as String,
              style: TextStyle(
                color: i == crumbs.length - 1
                    ? Colors.grey[800]
                    : AppColors.primaryBlue,
                fontWeight: i == crumbs.length - 1
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ============== Folder Card ==============

class _FolderCard extends StatelessWidget {
  final FolderModel folder;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const _FolderCard({
    required this.folder,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child:
                        const Icon(Icons.folder, color: Colors.amber, size: 28),
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'rename') onRename();
                      if (value == 'delete') onDelete();
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Rename'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                folder.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(folder.createdAt),
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}

// ============== File Card ==============

// ignore: unused_element
class _FileCard extends StatelessWidget {
  final FileModel file;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onMove;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  const _FileCard({
    required this.file,
    required this.onTap,
    required this.onRename,
    required this.onMove,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getFileColor(file.type).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getFileIcon(file.type),
                      color: _getFileColor(file.type),
                      size: 28,
                    ),
                  ),
                  const Spacer(),
                  if (file.sourceSheetId != null)
                    Tooltip(
                      message: 'Auto-saved from Sheet',
                      child:
                          Icon(Icons.sync, size: 16, color: Colors.blue[300]),
                    ),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          onRename();
                          break;
                        case 'move':
                          onMove();
                          break;
                        case 'download':
                          onDownload();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit, size: 18),
                            SizedBox(width: 8),
                            Text('Rename'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'move',
                        child: Row(
                          children: [
                            Icon(Icons.drive_file_move, size: 18),
                            SizedBox(width: 8),
                            Text('Move to Folder'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'download',
                        child: Row(
                          children: [
                            Icon(Icons.download, size: 18),
                            SizedBox(width: 8),
                            Text('Download'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Spacer(),
              Text(
                file.name,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '${file.rowCount ?? 0} rows • ${_formatDate(file.updatedAt)}',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
              if (file.activeUsers > 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.people, size: 12, color: Colors.green),
                    const SizedBox(width: 4),
                    Text(
                      '${file.activeUsers} editing',
                      style: const TextStyle(color: Colors.green, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'xlsx':
      case 'xls':
        return Icons.table_chart;
      case 'csv':
        return Icons.description;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'xlsx':
      case 'xls':
        return Colors.green;
      case 'csv':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.month}/${date.day}/${date.year}';
  }
}
