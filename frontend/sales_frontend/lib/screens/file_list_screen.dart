import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../providers/data_provider.dart';
import '../models/file.dart';
import '../services/api_service.dart';
import 'table_view_screen.dart';
import 'dart:io';

class FileListScreen extends StatefulWidget {
  const FileListScreen({super.key});

  @override
  State<FileListScreen> createState() => _FileListScreenState();
}

class _FileListScreenState extends State<FileListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadFiles();
    });
  }

  // ============== Dialogs ==============

  Future<String?> _showNameDialog({String title = 'Name', String? initialValue}) async {
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

  // ============== Actions ==============

  Future<void> _importFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls', 'csv'],
    );

    if (result != null && result.files.single.path != null && mounted) {
      final filePath = result.files.single.path!;
      final fileName = result.files.single.name;

      final name = await _showNameDialog(title: 'Import File');
      if (name != null && name.isNotEmpty) {
        final success = await context.read<DataProvider>().uploadFile(
              filePath,
              fileName,
              name,
            );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(success
                  ? 'File "$fileName" uploaded successfully!'
                  : 'Failed to upload file'),
              backgroundColor: success ? Colors.green : Colors.red,
            ),
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
      final success = await context.read<DataProvider>().createFolder(name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Folder "$name" created' : 'Failed to create folder'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _renameFile(FileModel file) async {
    final name = await _showNameDialog(title: 'Rename File', initialValue: file.name);
    if (name != null && name.isNotEmpty && mounted) {
      final success = await context.read<DataProvider>().renameFileItem(file.id, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'File renamed to "$name"' : 'Failed to rename file'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _renameFolder(FolderModel folder) async {
    final name = await _showNameDialog(title: 'Rename Folder', initialValue: folder.name);
    if (name != null && name.isNotEmpty && mounted) {
      final success = await context.read<DataProvider>().renameFolder(folder.id, name);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'Folder renamed to "$name"' : 'Failed to rename folder'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'File moved successfully' : 'Failed to move file'),
            backgroundColor: success ? Colors.green : Colors.red,
          ),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded to: $outputPath'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.red,
          ),
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

  // ============== Build ==============

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  if (data.isLoading && data.files.isEmpty && data.folders.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (data.files.isEmpty && data.folders.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
                          const SizedBox(height: 16),
                          Text(
                            data.currentFolderId == null
                                ? 'No files yet'
                                : 'This folder is empty',
                            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
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
                  final totalItems = folders.length + files.length;

                  return RefreshIndicator(
                    onRefresh: () => data.loadFiles(folderId: data.currentFolderId),
                    child: GridView.builder(
                      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 220,
                        childAspectRatio: 0.95,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: totalItems,
                      itemBuilder: (context, index) {
                        if (index < folders.length) {
                          final folder = folders[index];
                          return _FolderCard(
                            folder: folder,
                            onTap: () => data.navigateToFolder(folder.id, folder.name),
                            onRename: () => _renameFolder(folder),
                            onDelete: () => _confirmDeleteFolder(folder),
                          );
                        } else {
                          final file = files[index - folders.length];
                          return _FileCard(
                            file: file,
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TableViewScreen(file: file),
                                ),
                              );
                            },
                            onRename: () => _renameFile(file),
                            onMove: () => _moveFile(file),
                            onDownload: () => _downloadFile(file),
                            onDelete: () => _confirmDeleteFile(file),
                          );
                        }
                      },
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
              Icon(Icons.home, size: 18, color: crumbs.isEmpty ? Colors.grey[800] : Colors.blue),
              const SizedBox(width: 4),
              Text(
                'My Files',
                style: TextStyle(
                  color: crumbs.isEmpty ? Colors.grey[800] : Colors.blue,
                  fontWeight: crumbs.isEmpty ? FontWeight.bold : FontWeight.normal,
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
            onTap: i == crumbs.length - 1 ? null : () => data.navigateToBreadcrumb(i),
            child: Text(
              crumbs[i]['name'] as String,
              style: TextStyle(
                color: i == crumbs.length - 1 ? Colors.grey[800] : Colors.blue,
                fontWeight: i == crumbs.length - 1 ? FontWeight.bold : FontWeight.normal,
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
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.folder, color: Colors.amber, size: 28),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
                      color: _getFileColor(file.type).withOpacity(0.1),
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
                      child: Icon(Icons.sync, size: 16, color: Colors.blue[300]),
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
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
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
