import 'package:flutter/gestures.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:async';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../models/collaboration.dart';
import '../config/constants.dart';
import 'inventory_template_seed.dart';

/// Sheet model for spreadsheet data
class SheetModel {
  final int id;
  final String name;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final bool shownToViewers;
  final bool hasPassword;
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
    this.hasPassword = false,
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
      columns:
          json['columns'] != null ? List<String>.from(json['columns']) : [],
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
      hasPassword: json['has_password'] ?? false,
      lockedBy: json['locked_by'],
      lockedByName: json['locked_by_name'],
      lockedAt:
          json['locked_at'] != null ? DateTime.parse(json['locked_at']) : null,
      editingUserId: json['editing_user_id'],
      editingUserName: json['editing_user_name'],
    );
  }

  bool get isLocked => lockedBy != null;
  bool get isBeingEdited => editingUserId != null;
}

// ── Explorer types (used only inside the "All Sheets" container) ───────────
class _ExplorerFolderContents {
  final List<Map<String, dynamic>> folders;
  final List<SheetModel> sheets;

  const _ExplorerFolderContents({
    required this.folders,
    required this.sheets,
  });
}

enum _ExplorerEntryKind { folder, sheet, loading, emptyFolder }

class _ExplorerEntry {
  final _ExplorerEntryKind kind;
  final int depth;
  final Map<String, dynamic>? folder;
  final SheetModel? sheet;
  final bool? isExpanded;
  final bool? isLoading;

  const _ExplorerEntry._({
    required this.kind,
    required this.depth,
    this.folder,
    this.sheet,
    this.isExpanded,
    this.isLoading,
  });

  factory _ExplorerEntry.folder({
    required Map<String, dynamic> folder,
    required int depth,
    required bool isExpanded,
    required bool isLoading,
  }) {
    return _ExplorerEntry._(
      kind: _ExplorerEntryKind.folder,
      depth: depth,
      folder: folder,
      isExpanded: isExpanded,
      isLoading: isLoading,
    );
  }

  factory _ExplorerEntry.sheet({
    required SheetModel sheet,
    required int depth,
  }) {
    return _ExplorerEntry._(
      kind: _ExplorerEntryKind.sheet,
      depth: depth,
      sheet: sheet,
    );
  }

  factory _ExplorerEntry.loading({required int depth}) {
    return _ExplorerEntry._(kind: _ExplorerEntryKind.loading, depth: depth);
  }

  factory _ExplorerEntry.emptyFolder({required int depth}) {
    return _ExplorerEntry._(kind: _ExplorerEntryKind.emptyFolder, depth: depth);
  }
}

/// Represents one column formula row in the formula builder
class _FormulaEntry {
  String? resultCol;
  String op;
  List<String?> operandCols;

  _FormulaEntry({
    this.resultCol,
    this.op = '+',
    List<String?>? operandCols,
  }) : operandCols = operandCols ?? [null, null];

  _FormulaEntry copy() => _FormulaEntry(
        resultCol: resultCol,
        op: op,
        operandCols: List<String?>.from(operandCols),
      );
}

class _SheetSnapshot {
  final List<String> columns;
  final List<Map<String, String>> data;
  final List<String> rowLabels;
  final int? selectedRow;
  final int? selectedCol;
  final int? selectionEndRow;
  final int? selectionEndCol;

  const _SheetSnapshot({
    required this.columns,
    required this.data,
    required this.rowLabels,
    this.selectedRow,
    this.selectedCol,
    this.selectionEndRow,
    this.selectionEndCol,
  });
}

class SheetScreen extends StatefulWidget {
  final bool readOnly;
  final VoidCallback? onNavigateToEditRequests;

  const SheetScreen(
      {super.key, this.readOnly = false, this.onNavigateToEditRequests});

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

class _SheetScreenState extends State<SheetScreen> {
  List<SheetModel> _sheets = [];
  List<Map<String, dynamic>> _sheetFolders = [];
  int? _currentSheetFolderId;
  String? _currentSheetFolderName;
  List<Map<String, dynamic>> _sheetFolderBreadcrumbs = []; // [{id, name}]
  SheetModel? _currentSheet;
  bool _isLoading = true;
  int? _openingSheetId;

  // Explorer state (used only inside the "All Sheets" container)
  final Set<int> _explorerExpandedFolderIds = {};
  final Map<int, _ExplorerFolderContents> _explorerFolderCache = {};
  final Set<int> _explorerLoadingFolderIds = {};
  final Set<int> _explorerSelectedFolderIds = {};

  // Collaborative editing state
  bool _isLocked = false;
  String? _lockedByUser;
  bool _isEditingSession = false;
  String? _lastShownLockUser; // Track which lock user we already notified about

  // Spreadsheet state
  List<String> _columns = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];
  List<Map<String, String>> _data = [];
  List<String> _rowLabels = []; // Custom row labels
  int? _editingRow;
  int? _editingCol;
  String _saveStatus = 'saved'; // 'saved' | 'unsaved' | 'saving'
  bool _hasUnsavedChanges = false;
  String _originalCellValue = '';
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

  // Undo / Redo history
  static const int _maxHistoryEntries = 100;
  final List<_SheetSnapshot> _undoStack = [];
  final List<_SheetSnapshot> _redoStack = [];
  bool _isRestoringHistory = false;

  // Bulk sheet selection (All Sheets table)
  final Set<int> _selectedSheetIds = {};

  // Hover states (Work Sheets landing view)
  int? _hoveredAllSheetsRowIndex;
  int? _hoveredFolderId;
  int? _hoveredRecentSheetId;

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

  // Row heights and collapse state
  final Map<int, double> _rowHeights = {};
  final Set<int> _collapsedRows = {};
  static const double _collapsedRowHeight = 8.0;

  // Scroll controllers for synchronized scrolling
  final _horizontalScrollController = ScrollController();
  final _verticalScrollController = ScrollController();
  // Linked controllers for frozen column header and row numbers
  final _headerHScrollController = ScrollController();
  final _rowNumVScrollController = ScrollController();

  // Ribbon toolbar state
  String _selectedRibbonTab = 'File';

  // Inventory Tracker grid state
  bool _inventoryFilterWeek = false; // true = show only current-week dates
  bool _inventoryFilterToday = false; // true = show only today's column
  String _inventorySearchQuery = '';
  final TextEditingController _inventorySearchController =
      TextEditingController();
  double _criticalThreshold =
      0.80; // fraction used before red alert (default 80%)
  bool _invalidInventoryDialogOpen = false;

  // Zoom level for the spreadsheet grid
  double _zoomLevel = 1.0;
  static const double _zoomMin = 0.5;
  static const double _zoomMax = 2.0;
  static const double _zoomStep = 0.1;

  void _zoomIn() => setState(
      () => _zoomLevel = (_zoomLevel + _zoomStep).clamp(_zoomMin, _zoomMax));
  void _zoomOut() => setState(
      () => _zoomLevel = (_zoomLevel - _zoomStep).clamp(_zoomMin, _zoomMax));
  void _zoomReset() => setState(() => _zoomLevel = 1.0);

  // Column formula builder state — supports multiple formulas per sheet
  List<_FormulaEntry> _cfFormulas = [_FormulaEntry()];

  // Cell formatting state – key is "row,col"
  final Map<String, Set<String>> _cellFormats =
      {}; // e.g. {'bold','italic','underline'}
  final Map<String, double> _cellFontSizes = {}; // custom font size
  final Map<String, TextAlign> _cellAlignments = {}; // custom alignment
  final Map<String, Color> _cellTextColors = {}; // text color
  final Map<String, Color> _cellBackgroundColors = {}; // background color
  final Map<String, Map<String, bool>> _cellBorders =
      {}; // borders (top, right, bottom, left)
  final Set<String> _mergedCellRanges =
      {}; // merged cell ranges e.g., "1,1:2,3"
  double _currentFontSize = 13.0;
  Color _currentTextColor = Colors.black;
  Color _currentBackgroundColor = Colors.transparent;
  static const List<double> _fontSizeOptions = [
    10,
    11,
    12,
    13,
    14,
    16,
    18,
    20,
    24,
    28,
    32
  ];

  // Timer for periodic status updates
  Timer? _statusTimer;
  int _timerTick = 0; // counts 5-second ticks; every 2nd tick ≈ 10 s
  // Timer for debounced auto-save (fires 2 s after the last change)
  Timer? _autoSaveTimer;

  // ── V2 Collaboration: real-time presence & edit requests ──
  List<CellPresence> _presenceUsers = [];
  // Password protection: track items unlocked this session
  final Set<int> _unlockedFolderIds = {};
  final Set<int> _unlockedSheetIds = {};
  // cellRef (e.g. "B4") -> set of userId's currently on that cell
  final Map<String, Set<int>> _cellPresenceUserIds = {};
  // userId -> CellPresence lookup (populated from both presence_update & cell_focused)
  final Map<int, CellPresence> _presenceInfoMap = {};
  // cells for which THIS user has been granted temp edit access
  final Set<String> _grantedCells = {};
  // number of pending edit-requests visible to admin
  int _pendingEditRequestCount = 0;
  // Poll-based active users (DB-backed heartbeat)
  List<Map<String, dynamic>> _activeSheetUsers = [];

  bool _isPresenceRoleSupported(String role) {
    final normalized = role.trim().toLowerCase();
    return normalized.isEmpty ||
        normalized == 'admin' ||
        normalized == 'editor' ||
        normalized == 'viewer' ||
        normalized == 'manager' ||
        normalized == 'user';
  }

  CellPresence _pickRicherPresence(CellPresence current, CellPresence next) {
    int score(CellPresence u) {
      var s = 0;
      if (u.fullName.trim().isNotEmpty && u.fullName.trim() != u.username) s++;
      if (u.role.trim().isNotEmpty) s++;
      if ((u.departmentName ?? '').trim().isNotEmpty) s++;
      if ((u.currentCell ?? '').trim().isNotEmpty) s++;
      return s;
    }

    return score(next) >= score(current) ? next : current;
  }

  List<CellPresence> _buildEffectivePresenceUsers() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final authUser = authProvider.user;
    final usersById = <int, CellPresence>{};

    void upsert(CellPresence user) {
      if (user.userId <= 0) return;
      if (!_isPresenceRoleSupported(user.role)) return;
      final existing = usersById[user.userId];
      usersById[user.userId] =
          existing == null ? user : _pickRicherPresence(existing, user);
    }

    for (final user in _presenceInfoMap.values) {
      upsert(user);
    }
    for (final user in _presenceUsers) {
      upsert(user);
    }

    if (authUser != null) {
      upsert(CellPresence(
        userId: authUser.id,
        username: authUser.username,
        role: authUser.role,
        departmentName: authUser.departmentName,
        currentCell: null,
      ));
    }

    final authId = authUser?.id;
    final result = usersById.values.toList()
      ..sort((a, b) {
        if (authId != null) {
          if (a.userId == authId && b.userId != authId) return -1;
          if (b.userId == authId && a.userId != authId) return 1;
        }
        return a.username.toLowerCase().compareTo(b.username.toLowerCase());
      });

    return result;
  }

  Future<void> _heartbeatAndFetchActiveUsers() async {
    final sheetId = _currentSheet?.id;
    if (sheetId == null || !mounted) return;

    try {
      await ApiService.heartbeatSheetActiveUser(sheetId);
      final users = await ApiService.getSheetActiveUsers(sheetId);
      if (!mounted || _currentSheet?.id != sheetId) return;

      final authId = Provider.of<AuthProvider>(context, listen: false).user?.id;
      final normalized = users.map((u) {
        final uid = u['user_id'] is num
            ? (u['user_id'] as num).toInt()
            : int.tryParse('${u['user_id'] ?? ''}') ?? -1;
        final username = (u['username'] ?? '').toString();
        final fullName = (u['full_name'] ?? '').toString();
        final role = (u['role'] ?? '').toString();
        final department = (u['department_name'] ?? '').toString();
        return <String, dynamic>{
          'user_id': uid,
          'username': username,
          'full_name': fullName,
          'role': role,
          'department_name': department,
          'is_you': authId != null && uid == authId,
        };
      }).toList()
        ..sort((a, b) {
          final aYou = a['is_you'] == true;
          final bYou = b['is_you'] == true;
          if (aYou && !bYou) return -1;
          if (bYou && !aYou) return 1;
          return ('${a['username']}'.toLowerCase())
              .compareTo('${b['username']}'.toLowerCase());
        });

      final newSig = normalized
          .map((u) =>
              '${u['user_id']}|${u['username']}|${u['role']}|${u['department_name']}|${u['is_you']}')
          .toList();
      final oldSig = _activeSheetUsers
          .map((u) =>
              '${u['user_id']}|${u['username']}|${u['role']}|${u['department_name']}|${u['is_you']}')
          .toList();

      if (!listEquals(newSig, oldSig)) {
        setState(() => _activeSheetUsers = normalized);
      }

      if (kDebugMode) {
        debugPrint(
            '[ActiveUsers] sheet=$sheetId total=${normalized.length} users=${normalized.map((u) => u['username']).join(', ')}');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[ActiveUsers] sync failed for sheet=$sheetId: $e');
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _initializeSheet();
    _loadSheets();
    _setupSheetPresenceCallbacks();

    // Refresh presence every 5 s, and also refresh sheet data + status as
    // a safety-net fallback for any missed socket events.
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _timerTick++;
      _refreshSheetStatus();
      // Presence: request the full list every 5 s so any missed join/leave
      // event self-corrects within 5 seconds.
      if (_currentSheet != null) {
        SocketService.instance.getPresence(_currentSheet!.id);
        _heartbeatAndFetchActiveUsers();
      }
      // DB reload: only every 2nd tick (~10 s) to avoid hammering the server.
      if (_timerTick % 2 == 0 &&
          !_hasUnsavedChanges &&
          _editingRow == null &&
          _currentSheet != null) {
        _reloadSheetDataOnly();
      }
    });

    // Sync column headers horizontal scroll with main grid horizontal scroll
    _horizontalScrollController.addListener(() {
      if (_headerHScrollController.hasClients) {
        _headerHScrollController.jumpTo(_horizontalScrollController.offset
            .clamp(0, _headerHScrollController.position.maxScrollExtent));
      }
    });
    // Sync row numbers vertical scroll with main grid vertical scroll
    _verticalScrollController.addListener(() {
      if (_rowNumVScrollController.hasClients) {
        _rowNumVScrollController.jumpTo(_verticalScrollController.offset
            .clamp(0, _rowNumVScrollController.position.maxScrollExtent));
      }
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
            content: Text(showToViewers
                ? 'Sheet is now visible to viewers'
                : 'Sheet is now hidden from viewers'),
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

  // ── Password protection helpers ──

  /// Show dialog to enter password; returns true if verification passed.
  // ignore: unused_element
  Future<bool> _showVerifyPasswordDialog(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Enter password',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(true),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Unlock')),
        ],
      ),
    );
    if (result != true) return false;
    return controller
        .text.isNotEmpty; // actual verification done via API in callers
  }

  /// Show dialog to set (or remove) a password. Returns null if cancelled,
  /// empty string to remove, or a non-empty string to set.
  Future<String?> _showSetPasswordDialog({
    required String title,
    required bool hasPassword,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        surfaceTintColor: Colors.transparent,
        title: Text(title, style: TextStyle(color: _textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hasPassword)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'A password is already set. Enter a new one to change it, or leave blank to remove it.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Anyone opening this item will need to enter this password.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
              ),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'New password (blank to remove)',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: _surfaceAltColor,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: Text('Cancel', style: TextStyle(color: _textSecondary))),
          if (hasPassword)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('Remove Password',
                  style: TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _setSheetPassword(SheetModel sheet) async {
    final newPw = await _showSetPasswordDialog(
        title: 'Set Password — ${sheet.name}', hasPassword: sheet.hasPassword);
    if (newPw == null) return; // cancelled
    try {
      final res = await ApiService.setSheetPassword(
          sheet.id, newPw.isEmpty ? null : newPw);
      if (res['success'] == true) {
        await _loadSheets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(newPw.isEmpty ? 'Password removed' : 'Password set'),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _setFolderPassword(Map<String, dynamic> folder) async {
    final hasPassword = folder['has_password'] == true;
    final newPw = await _showSetPasswordDialog(
        title: 'Set Password — ${folder['name']}', hasPassword: hasPassword);
    if (newPw == null) return;
    try {
      final res = await ApiService.setFolderPassword(
          folder['id'] as int, newPw.isEmpty ? null : newPw);
      if (res['success'] == true) {
        await _loadSheets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(newPw.isEmpty ? 'Password removed' : 'Password set'),
            backgroundColor: Colors.green,
          ));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _openFolderWithPasswordCheck(Map<String, dynamic> folder) async {
    final id = folder['id'] as int;
    final hasPassword = folder['has_password'] == true;
    final role = context.read<AuthProvider>().user?.role;
    // Only admins bypass the password check.
    if (!hasPassword || role == 'admin' || _unlockedFolderIds.contains(id)) {
      _navigateIntoSheetFolder(id, folder['name'] as String);
      return;
    }
    final controller = TextEditingController();
    String? errorText;
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDialog) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.lock, size: 20),
              SizedBox(width: 8),
              Text('Password Required'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  '"${folder['name']}" is protected. Enter its password to open it.'),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Password',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
                onSubmitted: (_) => Navigator.of(ctx2).pop(true),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx2).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(ctx2).pop(true),
                child: const Text('Open')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      final res = await ApiService.verifyFolderPassword(id, controller.text);
      if (res['success'] == true) {
        _unlockedFolderIds.add(id);
        _navigateIntoSheetFolder(id, folder['name'] as String);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Incorrect password'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Incorrect password'), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _openSheetWithPasswordCheck(SheetModel sheet) async {
    if (!sheet.hasPassword || _unlockedSheetIds.contains(sheet.id)) {
      if (mounted) setState(() => _openingSheetId = sheet.id);
      try {
        await _loadSheetData(sheet.id);
      } finally {
        if (mounted && _openingSheetId == sheet.id) {
          setState(() => _openingSheetId = null);
        }
      }
      return;
    }
    final role = context.read<AuthProvider>().user?.role;
    // Only admins bypass the password check.
    if (role == 'admin') {
      if (mounted) setState(() => _openingSheetId = sheet.id);
      try {
        await _loadSheetData(sheet.id);
      } finally {
        if (mounted && _openingSheetId == sheet.id) {
          setState(() => _openingSheetId = null);
        }
      }
      return;
    }
    final controller = TextEditingController();
    bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.lock, size: 20),
            SizedBox(width: 8),
            Text('Password Required'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                '"${sheet.name}" is protected. Enter its password to open it.'),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Password',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Open')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final res =
          await ApiService.verifySheetPassword(sheet.id, controller.text);
      if (res['success'] == true) {
        _unlockedSheetIds.add(sheet.id);
        if (mounted) setState(() => _openingSheetId = sheet.id);
        try {
          await _loadSheetData(sheet.id);
        } finally {
          if (mounted && _openingSheetId == sheet.id) {
            setState(() => _openingSheetId = null);
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Incorrect password'),
              backgroundColor: Colors.red));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Incorrect password'), backgroundColor: Colors.red));
      }
    }
  }

  /// Lock sheet for editing
  Future<void> _lockSheet() async {
    if (_currentSheet == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.lockSheet(_currentSheet!.id);
      await _refreshSheetStatus();
      await _startEditSession();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sheet locked for editing'),
            backgroundColor: AppColors.primaryBlue,
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Unlock sheet
  Future<void> _unlockSheet() async {
    if (_currentSheet == null || !mounted) return;

    setState(() => _isLoading = true);

    try {
      await ApiService.unlockSheet(_currentSheet!.id);
      await _refreshSheetStatus();

      if (mounted) setState(() => _isEditingSession = false);

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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Start edit session
  Future<void> _startEditSession() async {
    if (_currentSheet == null || !mounted) return;

    try {
      await ApiService.startEditSession(_currentSheet!.id);
      if (!mounted) return;
      setState(() => _isEditingSession = true);

      // Start periodic heartbeat
      _startEditSessionHeartbeat();
    } catch (e) {
      debugPrint('Failed to start edit session: $e');
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
          debugPrint('Edit session heartbeat failed: $e');
        }
      }
    });
  }

  /// Refresh sheet status (locks and active editors)
  Future<void> _refreshSheetStatus() async {
    if (_currentSheet == null || !mounted) return;

    try {
      final response = await ApiService.getSheetStatus(_currentSheet!.id);
      if (!mounted) return;
      final status = response['status'];

      setState(() {
        _isLocked = status['is_locked'] ?? false;
        _lockedByUser = status['locked_by'];
      });

      // Show one-time snackbar when a different user locks the sheet
      if (mounted && _isLocked && _lockedByUser != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUsername = authProvider.user?.username ?? '';
        if (_lockedByUser != currentUsername &&
            _lastShownLockUser != _lockedByUser) {
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
      debugPrint('Failed to refresh sheet status: $e');
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
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.getSheets(
        folderId: _currentSheetFolderId,
        rootOnly: _currentSheetFolderId == null,
      );
      if (!mounted) return;
      setState(() {
        _sheets = (response['sheets'] as List?)
                ?.map((s) => SheetModel.fromJson(s))
                .toList() ??
            [];
        _sheetFolders = (response['folders'] as List?)
                ?.cast<Map<String, dynamic>>()
                .toList() ??
            [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSheetData(int sheetId) async {
    if (!mounted) return;

    // ── Leave the previous sheet room so the backend cleans up presence ──────
    if (_currentSheet != null && _currentSheet!.id != sheetId) {
      SocketService.instance.leaveSheet(_currentSheet!.id);
    }

    // ── Clear stale presence data so old avatars don't linger ────────────────
    if (_currentSheet?.id != sheetId) {
      _presenceUsers = [];
      _cellPresenceUserIds.clear();
      _presenceInfoMap.clear();
      _activeSheetUsers = [];
    }

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.getSheetData(sheetId);
      if (!mounted) return;
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

        // Strip legacy Inventory Tracker columns that are no longer used.
        if (_columns.contains('Product Name') &&
            (_columns.contains('QB Code') || _columns.contains('QC Code')) &&
            _columns.contains('Total Quantity')) {
          const legacy = ['Reference No.', 'Remarks', 'Date', 'IN', 'OUT'];
          for (final col in legacy) {
            _columns.remove(col);
            for (final row in _data) {
              row.remove(col);
            }
          }

          // Ensure modern Inventory Tracker has a dedicated Stock column.
          if (!_columns.contains('Stock')) {
            final maintainingIdx = _columns.indexOf('Maintaining');
            final insertAt = maintainingIdx >= 0 ? maintainingIdx : 2;
            _columns.insert(insertAt, 'Stock');
            for (final row in _data) {
              final current = (row['Total Quantity'] ?? '').trim();
              row['Stock'] = current.isEmpty ? '0' : current;
            }
          }

          // Ensure Inventory Tracker has a dedicated Critical threshold column.
          if (!_columns.contains('Critical')) {
            final maintainingIdx = _columns.indexOf('Maintaining');
            final insertAt = maintainingIdx >= 0 ? maintainingIdx + 1 : 4;
            _columns.insert(insertAt, 'Critical');
            for (final row in _data) {
              final maintaining = (row['Maintaining'] ?? '').trim();
              row['Critical'] = maintaining.isEmpty ? '0' : maintaining;
            }
          }
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
        _saveStatus = 'saved';
        _hasUnsavedChanges = false;
      });
      if (mounted) {
        context.read<DataProvider>().setCurrentSheet(
              sheetId: sheet.id,
              sheetName: sheet.name,
            );
      }
      _clearHistory();

      // Refresh collaborative editing status
      await _refreshSheetStatus();

      if (!mounted) return;
      // Auto-inject today's date column for Inventory Tracker sheets.
      _autoInjectTodayColumnIfNeeded();

      // Announce presence in this sheet room via socket.
      final currentSheetId = _currentSheet!.id;
      SocketService.instance.joinSheet(currentSheetId);
      _heartbeatAndFetchActiveUsers();

      // Request the full presence list immediately (0 ms) so we see
      // users who were already in the sheet BEFORE we joined, then
      // retry at increasing intervals to self-heal any missed events.
      for (final ms in const [0, 300, 800, 2000, 5000]) {
        Future.delayed(Duration(milliseconds: ms), () {
          if (mounted && _currentSheet?.id == currentSheetId) {
            SocketService.instance.getPresence(currentSheetId);
          }
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
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

      // If currently inside a folder, move the new sheet into it
      if (_currentSheetFolderId != null) {
        try {
          await ApiService.moveSheetToFolder(sheet.id, _currentSheetFolderId);
        } catch (_) {}
      }

      if (!mounted) return;
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
      _clearHistory();

      // Keep dashboard context in sync.
      if (mounted) {
        context.read<DataProvider>().setCurrentSheet(
              sheetId: sheet.id,
              sheetName: sheet.name,
            );
        context.read<DataProvider>().loadInventorySheets();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('New sheet created'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create sheet: $e')),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  Sheet Templates
  // ════════════════════════════════════════════

  /// All built-in templates available for sheet creation
  static const List<Map<String, dynamic>> _kTemplates = [
    {
      'id': 'inventory_tracker',
      'name': 'Inventory Tracker',
      'description':
          'Product inventory with daily IN/OUT transactions, stock thresholds, and running totals.',
      'iconData': 0xe1d1, // Icons.inventory codepoint
      'colorValue': 0xFF1E3A6E,
      'columns': [
        'Product Name',
        'QC Code',
        'Stock',
        'Maintaining',
        'Critical',
        'Total Quantity',
      ],
      'rows': kInventoryTrackerSeedRows,
    },
    {
      'id': 'sales_report',
      'name': 'Sales Report',
      'description': 'Daily or monthly sales log with totals per product.',
      'iconData': 0xe126, // Icons.bar_chart codepoint
      'colorValue': 0xFFBF360C,
      'columns': [
        'Date',
        'Product',
        'Quantity',
        'Unit Price',
        'Total',
        'Customer',
        'Notes',
      ],
      'rows': [
        {
          'Date': '',
          'Product': '',
          'Quantity': '0',
          'Unit Price': '0',
          'Total': '0',
          'Customer': '',
          'Notes': '',
        },
      ],
    },
    {
      'id': 'purchase_order',
      'name': 'Purchase Order',
      'description': 'Track purchase orders from suppliers.',
      'iconData': 0xe1b2, // Icons.receipt_long codepoint
      'colorValue': 0xFF6A1B9A,
      'columns': [
        'Date',
        'Supplier',
        'Product',
        'Quantity',
        'Unit Price',
        'Total',
        'Status',
        'Remarks',
      ],
      'rows': [
        {
          'Date': '',
          'Supplier': '',
          'Product': '',
          'Quantity': '0',
          'Unit Price': '0',
          'Total': '0',
          'Status': 'Pending',
          'Remarks': '',
        },
      ],
    },
    {
      'id': 'employee_attendance',
      'name': 'Employee Attendance',
      'description': 'Track daily attendance, hours, and overtime.',
      'iconData': 0xe7fb, // Icons.people codepoint
      'colorValue': 0xFF00695C,
      'columns': [
        'Date',
        'Employee ID',
        'Employee Name',
        'Time In',
        'Time Out',
        'Hours',
        'Overtime',
        'Remarks',
      ],
      'rows': [
        {
          'Date': '',
          'Employee ID': '',
          'Employee Name': '',
          'Time In': '',
          'Time Out': '',
          'Hours': '0',
          'Overtime': '0',
          'Remarks': '',
        },
      ],
    },
  ];

  /// Show the template picker dialog, then create a sheet from the chosen template
  Future<void> _showTemplatePickerDialog() async {
    final template = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => const _TemplatePickerDialog(),
    );
    if (template == null || !mounted) return;

    // Ask for the sheet name (pre-fill with template name)
    final name = await _showNameDialog(
      'Name Your Sheet',
      'Sheet name',
      initialValue: template['name'] as String,
    );
    if (name == null || name.trim().isEmpty) return;

    await _createSheetFromTemplate(name.trim(), template);
  }

  /// Create a sheet pre-loaded with a template's columns and sample rows
  Future<void> _createSheetFromTemplate(
      String name, Map<String, dynamic> template) async {
    setState(() => _isLoading = true);
    try {
      final cols = List<String>.from(template['columns'] as List);

      // ── Inventory Tracker: inject today's date column automatically ──
      if (template['id'] == 'inventory_tracker') {
        final todayStr = _inventoryDateStr(DateTime.now());
        final totalIdx = cols.indexOf('Total Quantity');
        final insertAt = totalIdx < 0 ? cols.length - 1 : totalIdx;
        cols.insert(insertAt, 'DATE:$todayStr:IN');
        cols.insert(insertAt + 1, 'DATE:$todayStr:OUT');
      }

      final response = await ApiService.createSheet(name, cols);
      final sheet = SheetModel.fromJson(response['sheet']);

      // Move into current folder if applicable
      if (_currentSheetFolderId != null) {
        try {
          await ApiService.moveSheetToFolder(sheet.id, _currentSheetFolderId);
        } catch (_) {}
      }

      // Build row data from template sample rows, padded to 100 rows
      final templateRows =
          List<Map<String, dynamic>>.from(template['rows'] as List);
      final initialRowCount = templateRows.length.clamp(1, 10000);
      final data = List<Map<String, String>>.generate(initialRowCount, (i) {
        final row = <String, String>{};
        for (final col in cols) {
          // For DATE:* columns not in the template, default to empty string
          row[col] = i < templateRows.length
              ? (templateRows[i][col]?.toString() ?? '')
              : '';
        }
        return row;
      });

      // Pre-save the sample rows so they appear immediately
      if (templateRows.isNotEmpty) {
        try {
          await ApiService.updateSheet(
            sheet.id,
            name,
            cols,
            data
                .take(templateRows.length)
                .map((r) => Map<String, dynamic>.from(r))
                .toList(),
          );
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _sheets.insert(0, sheet);
        _currentSheet = sheet;
        _columns = cols;
        _data = data;
        _rowLabels = List.generate(initialRowCount, (i) => '${i + 1}');
        _selectedRow = null;
        _selectedCol = null;
        _selectionEndRow = null;
        _selectionEndCol = null;
        _editingRow = null;
        _editingCol = null;
        _isLoading = false;
      });
      _clearHistory();

      // Inventory dashboard sheet filter is driven by DataProvider.
      if (mounted) {
        context.read<DataProvider>().setCurrentSheet(
              sheetId: sheet.id,
              sheetName: sheet.name,
            );
        context.read<DataProvider>().loadInventorySheets();
      }

      // Recalc totals so Stock/Total Quantity reflect IN/OUT values.
      if (template['id'] == 'inventory_tracker') {
        _recalcInventoryTotals();
        await _saveSheet();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Sheet "$name" created from ${template['name']} template'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create from template: $e')),
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  Folder Management
  // ════════════════════════════════════════════

  Future<String?> _showFolderNameDialog(
      {String title = 'New Folder', String? initialValue}) async {
    final controller = TextEditingController(text: initialValue ?? '');
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.create_new_folder,
                color: Colors.amber,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create a new folder to organize your worksheets',
              style: TextStyle(fontSize: 14, color: _textSecondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Folder Name',
                hintText: 'Enter folder name',
                prefixIcon: const Icon(Icons.folder_outlined),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: _surfaceAltColor,
              ),
              onSubmitted: (val) => Navigator.pop(context, val),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: _textSecondary),
            ),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, controller.text),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('Create'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kNavy,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showCreateFolderDialog() async {
    // Fetch all folders so user can choose where to create the new folder.
    List<Map<String, dynamic>> allFolders = [];
    try {
      final response = await ApiService.getSheetFolders();
      allFolders = (response['folders'] as List?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          [];
    } catch (_) {}

    if (!mounted) return;

    final folderIds = allFolders
        .map((f) => (f['id'] is int)
            ? f['id'] as int
            : int.tryParse(f['id']?.toString() ?? ''))
        .whereType<int>()
        .toSet();

    // Default location:
    // - current folder if browsing inside one
    // - else, if exactly one folder is selected in the explorer, use that
    // - else root
    int? initialParentId = _currentSheetFolderId;
    if (initialParentId == null && _explorerSelectedFolderIds.length == 1) {
      initialParentId = _explorerSelectedFolderIds.first;
    }
    if (initialParentId != null && !folderIds.contains(initialParentId)) {
      initialParentId = null;
    }

    final nameController = TextEditingController();
    int? selectedParentId = initialParentId;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setStateDialog) => AlertDialog(
          backgroundColor: _surfaceColor,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(_isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.create_new_folder,
                  color: Colors.amber,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'New Folder',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Choose where to create this folder',
                  style: TextStyle(fontSize: 14, color: _textSecondary),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  value: selectedParentId,
                  decoration: InputDecoration(
                    labelText: 'Location',
                    prefixIcon: const Icon(Icons.folder_open_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: _surfaceAltColor,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Root (No Folder)'),
                    ),
                    ...allFolders.map((folder) {
                      final id = (folder['id'] is int)
                          ? folder['id'] as int
                          : int.tryParse(folder['id']?.toString() ?? '');
                      final name = folder['name']?.toString() ?? 'Folder';
                      if (id == null) {
                        return DropdownMenuItem<int?>(
                          value: null,
                          enabled: false,
                          child: Text(name, overflow: TextOverflow.ellipsis),
                        );
                      }
                      return DropdownMenuItem<int?>(
                        value: id,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (v) => setStateDialog(() => selectedParentId = v),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Folder Name',
                    hintText: 'Enter folder name',
                    prefixIcon: const Icon(Icons.folder_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    fillColor: _surfaceAltColor,
                  ),
                  onSubmitted: (val) => Navigator.pop(ctx2, {
                    'name': val,
                    'parent_id': selectedParentId,
                  }),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx2),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx2, {
                'name': nameController.text,
                'parent_id': selectedParentId,
              }),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Create'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _kNavy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final name = result?['name']?.toString();
    final parentId = result?['parent_id'] as int?;

    if (name != null && name.trim().isNotEmpty && mounted) {
      // Validate folder name
      final trimmedName = name.trim();

      if (trimmedName.length < 2) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Folder name must be at least 2 characters'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      }

      if (trimmedName.length > 50) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Folder name must be less than 50 characters'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      }

      // Check for invalid characters
      final invalidChars = RegExp(r'[<>:"/\\|?*]');
      if (invalidChars.hasMatch(trimmedName)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Folder name contains invalid characters'),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
        return;
      }

      // Create the folder in current Sheets folder context
      bool success = false;
      debugPrint(
        '[folders:create:sheet] payload => {name: $trimmedName, parent_id: $parentId}',
      );
      try {
        await ApiService.createSheetFolder(
          trimmedName,
          parentId: parentId,
        );
        await _loadSheets();

        // Update the All Sheets explorer immediately:
        // - its folder children are cached, so refresh the parent folder
        // - expand the full ancestor chain so nested destinations become visible
        if (mounted && parentId != null) {
          final byId = <int, Map<String, dynamic>>{};
          for (final f in allFolders) {
            final id = (f['id'] is int)
                ? f['id'] as int
                : int.tryParse(f['id']?.toString() ?? '');
            if (id != null) byId[id] = f;
          }

          final ancestorIds = <int>[];
          int? cur = parentId;
          while (cur != null) {
            ancestorIds.add(cur);
            final folder = byId[cur];
            final next = (folder?['parent_id'] is int)
                ? folder!['parent_id'] as int
                : int.tryParse(folder?['parent_id']?.toString() ?? '');
            cur = next;
          }

          // Expand from root -> leaf so the tree opens smoothly.
          final chain = ancestorIds.reversed.toList(growable: false);
          setState(() => _explorerExpandedFolderIds.addAll(chain));

          // Ensure each expanded folder has cached children;
          // force refresh on the direct parent so the new folder appears.
          for (final id in chain) {
            await _ensureExplorerFolderLoaded(
              id,
              forceRefresh: id == parentId,
            );
          }
        }
        success = true;
      } catch (_) {
        success = false;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  success ? Icons.check_circle : Icons.error_outline,
                  color: Colors.white,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    success
                        ? 'Folder "$trimmedName" created successfully'
                        : 'Failed to create folder',
                  ),
                ),
              ],
            ),
            backgroundColor: success ? Colors.green : Colors.red,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    }
  }

  // ── Sheet Folder Navigation ──
  void _navigateIntoSheetFolder(int folderId, String folderName) {
    setState(() {
      _sheetFolderBreadcrumbs.add({
        'id': _currentSheetFolderId,
        'name': _currentSheetFolderName ?? 'Home'
      });
      _currentSheetFolderId = folderId;
      _currentSheetFolderName = folderName;
    });
    _loadSheets();
  }

  void _navigateToSheetBreadcrumb(int index) {
    final target = _sheetFolderBreadcrumbs[index];
    setState(() {
      _sheetFolderBreadcrumbs = _sheetFolderBreadcrumbs.sublist(0, index);
      _currentSheetFolderId = target['id'] as int?;
      _currentSheetFolderName = target['name'] as String?;
    });
    _loadSheets();
  }

  void _navigateToSheetRoot() {
    setState(() {
      _sheetFolderBreadcrumbs.clear();
      _currentSheetFolderId = null;
      _currentSheetFolderName = null;
    });
    _loadSheets();
  }

  Future<void> _showMoveSheetToFolderDialog(SheetModel sheet) async {
    // Fetch all folders
    List<Map<String, dynamic>> allFolders = [];
    try {
      final response = await ApiService.getSheetFolders();
      allFolders = (response['folders'] as List?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          [];
    } catch (_) {}

    if (!mounted) return;

    final selectedFolderId = await showDialog<int?>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _surfaceColor,
          surfaceTintColor: Colors.transparent,
          title: Row(
            children: [
              Icon(Icons.drive_file_move_outlined, color: _kBlue),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('Move "${sheet.name}"',
                      overflow: TextOverflow.ellipsis)),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Select destination:',
                    style: TextStyle(fontSize: 13, color: _textSecondary)),
                const SizedBox(height: 8),
                // Root option
                ListTile(
                  dense: true,
                  leading: Icon(Icons.home_outlined, color: _textSecondary),
                  title: const Text('Root (No Folder)'),
                  onTap: () => Navigator.pop(ctx, -1), // -1 means root
                ),
                const Divider(height: 1),
                if (allFolders.isEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('No folders available. Create one first.',
                        style: TextStyle(color: _textSecondary, fontSize: 13)),
                  )
                else
                  ...allFolders.map((folder) => ListTile(
                        dense: true,
                        leading: const Icon(Icons.folder_outlined,
                            color: Color(0xFFFFB300)),
                        title: Text(folder['name'] ?? ''),
                        subtitle: folder['sheet_count'] != null
                            ? Text('${folder['sheet_count']} sheets',
                                style: TextStyle(
                                    fontSize: 11, color: _textSecondary))
                            : null,
                        onTap: () => Navigator.pop(ctx, folder['id'] as int),
                      )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
          ],
        );
      },
    );

    if (selectedFolderId == null) return; // cancelled

    final targetFolderId = selectedFolderId == -1 ? null : selectedFolderId;

    try {
      await ApiService.moveSheetToFolder(sheet.id, targetFolderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(targetFolderId == null
                ? '"${sheet.name}" moved to root'
                : '"${sheet.name}" moved to folder'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        _loadSheets();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to move sheet: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Mark the sheet as having unsaved changes.
  void _markDirty() {
    if (!_hasUnsavedChanges || _saveStatus != 'unsaved') {
      setState(() {
        _hasUnsavedChanges = true;
        _saveStatus = 'unsaved';
      });
    }
    // Debounced auto-save: persist to DB 2 s after the last change so that
    // users who reload the sheet always see up-to-date data even when the
    // editor has not pressed the manual Save button.
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && _hasUnsavedChanges) _saveSheet();
    });
  }

  Future<void> _saveSheet() async {
    if (_currentSheet == null) {
      await _createNewSheet();
      return;
    }

    // Nothing changed – skip the round-trip entirely.
    if (!_hasUnsavedChanges) return;

    // Check if sheet is locked by another user
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (_isLocked &&
        _lockedByUser != null &&
        _lockedByUser != authProvider.user?.username &&
        authProvider.user?.role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Cannot save: $_lockedByUser is currently editing this sheet'),
          backgroundColor: Colors.orange[700],
        ),
      );
      return;
    }

    // Use _saveStatus for the indicator; do NOT touch _isLoading so the
    // grid is never replaced by a spinner during a background save.
    setState(() => _saveStatus = 'saving');

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
        setState(() {
          _saveStatus = 'saved';
          _hasUnsavedChanges = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saveStatus = 'unsaved');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<String?> _showNameDialog(String title, String hint,
      {String? initialValue}) async {
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

    if (newLabel == null || newLabel.isEmpty || newLabel == currentLabel) {
      return;
    }

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

    if (newName == null ||
        newName.trim().isEmpty ||
        newName.trim() == sheet.name) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await ApiService.renameSheet(sheet.id, newName.trim());
      if (!mounted) return;

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

      if (!mounted) return;
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
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to rename sheet: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _confirmDeleteSheet(SheetModel sheet) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';

    // Check permissions - only admin can delete
    if (userRole != 'admin') {
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

  Future<void> _bulkDeleteSheets() async {
    if (_selectedSheetIds.isEmpty) return;
    final count = _selectedSheetIds.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Selected Sheets'),
        content: Text(
            'Permanently delete $count sheet${count > 1 ? 's' : ''}? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(_, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isLoading = true);
    for (final id in List<int>.from(_selectedSheetIds)) {
      try {
        await ApiService.deleteSheet(id);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _selectedSheetIds.clear());
    await _loadSheets();
  }

  Future<void> _bulkMoveSheets() async {
    if (_selectedSheetIds.isEmpty) return;
    List<Map<String, dynamic>> allFolders = [];
    try {
      final response = await ApiService.getSheetFolders();
      allFolders = (response['folders'] as List?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          [];
    } catch (_) {}
    if (!mounted) return;
    final selectedFolderId = await showDialog<int?>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Root (no folder)'),
                onTap: () => Navigator.pop(_, -1),
              ),
              const Divider(height: 1),
              ...allFolders.map((f) => ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(f['name'] ?? ''),
                    onTap: () => Navigator.pop(_, f['id'] as int),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(_), child: const Text('Cancel')),
        ],
      ),
    );
    if (selectedFolderId == null || !mounted) return;
    final targetId = selectedFolderId == -1 ? null : selectedFolderId;
    setState(() => _isLoading = true);
    for (final id in List<int>.from(_selectedSheetIds)) {
      try {
        await ApiService.moveSheetToFolder(id, targetId);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _selectedSheetIds.clear());
    await _loadSheets();
  }

  Future<void> _deleteSheet(int sheetId) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await ApiService.deleteSheet(sheetId);
      if (!mounted) return;

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
        if (mounted) {
          context.read<DataProvider>().clearCurrentSheet();
        }
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

    _pushUndoSnapshot();
    setState(() {
      _columns.add(nextCol);
      for (var row in _data) {
        row[nextCol] = '';
      }
    });
    _markDirty();
  }

  void _addRow() {
    _pushUndoSnapshot();
    setState(() {
      final row = <String, String>{};
      for (var col in _columns) {
        row[col] = '';
      }
      _data.add(row);
      // Add label for new row
      _rowLabels.add('${_data.length}');
    });
    _markDirty();
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

    _pushUndoSnapshot();
    setState(() {
      _columns.removeAt(_selectedCol!);
      // Remove column data from all rows
      for (var row in _data) {
        row.remove(colToDelete);
      }
      _selectedCol = null;
      _selectionEndCol = null;
    });
    _markDirty();

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

    _pushUndoSnapshot();
    setState(() {
      _data.removeAt(_selectedRow!);
      _rowLabels.removeAt(_selectedRow!);
      _selectedRow = null;
      _selectionEndRow = null;
    });
    _markDirty();

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
      final fileBytes =
          await ApiService.exportSheet(_currentSheet!.id, format: format);

      // Save file with timestamp to avoid conflicts
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName =
          '${_currentSheet!.name.replaceAll(' ', '_')}_$timestamp.$format';
      final outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save file',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [format],
      );

      if (outputPath != null) {
        try {
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
        } catch (fileError) {
          if (mounted) {
            String errorMessage = 'Failed to save file';
            if (fileError
                .toString()
                .contains('being used by another process')) {
              errorMessage =
                  'Cannot save file: It is already open in another program. Please close the file and try again.';
            } else if (fileError.toString().contains('PathAccessException')) {
              errorMessage =
                  'Cannot access file: Please check if the file is open in another program or if you have write permissions.';
            } else {
              errorMessage = 'Failed to save file: ${fileError.toString()}';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(errorMessage),
                backgroundColor: Colors.red,
                duration: const Duration(seconds: 5),
              ),
            );
          }
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
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.first;
      final bytes = file.bytes;
      final fileName = file.name;

      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Could not read file'),
                backgroundColor: Colors.red),
          );
        }
        return;
      }

      setState(() => _isLoading = true);

      final response = await ApiService.importSheetFromBytes(
        bytes: bytes,
        fileName: fileName,
      );

      final sheet = SheetModel.fromJson(response['sheet']);
      final rowCount = response['rowCount'] ?? 0;
      final colCount = response['columnCount'] ?? 0;

      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Imported "${sheet.name}" — $rowCount rows, $colCount columns',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'Open',
              textColor: Colors.white,
              onPressed: () => _loadSheetData(sheet.id),
            ),
          ),
        );
        // Refresh the sheet list so the new sheet appears
        _loadSheets();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
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

    // Inventory Tracker: block editing of historical past-date columns for non-admins
    if (role != 'admin' && _isInventoryHistoricalCell(row, col)) {
      final cellRef = _getCellReference(row, col);
      if (!_grantedCells.contains(cellRef)) {
        _showEditRequestDialog(row, col);
        return;
      }
      // Has temp access — allow the edit; access removed after save via _saveEditWithGrantedCell
    }

    // Prevent editing if sheet is locked by another user
    if (_isLocked &&
        _lockedByUser != null &&
        _lockedByUser != authProvider.user?.username) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$_lockedByUser is currently editing this sheet'),
          backgroundColor: Colors.orange[700],
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Block editing if another user is currently focused on this cell
    final cellRef = _getCellReference(row, col);
    final authId = authProvider.user?.id ?? -1;
    final occupants = (_cellPresenceUserIds[cellRef] ?? <int>{})
        .where((id) => id != authId)
        .toList();
    if (occupants.isNotEmpty) {
      final name =
          _presenceInfoMap[occupants.first]?.username ?? 'Another user';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name is currently editing this cell'),
          backgroundColor: Colors.orange[700],
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() {
      _editingRow = row;
      _editingCol = col;
      _originalCellValue = _data[row][_columns[col]] ?? '';
      _editController.text = _originalCellValue;
    });
    // Broadcast cell focus to other collaborators
    if (_currentSheet != null) {
      SocketService.instance
          .cellFocus(_currentSheet!.id, _getCellReference(row, col));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  void _saveEdit() {
    if (_editingRow != null && _editingCol != null) {
      final savedRow = _editingRow!;
      final savedCol = _editingCol!;
      final cellRef = _getCellReference(savedRow, savedCol);
      final colName = _columns[savedCol];
      final newValue = _editController.text;
      if (_handleInvalidInventoryOutSubmission(
        rowIndex: savedRow,
        colName: colName,
        proposedValueRaw: newValue,
        previousValue: _originalCellValue,
        cellRef: cellRef,
      )) {
        return;
      }
      final changed = newValue != _originalCellValue;
      if (changed) {
        _pushUndoSnapshot();
      }
      setState(() {
        _data[savedRow][colName] = newValue;
        _editingRow = null;
        _editingCol = null;
        _updateFormulaBar();
        // Consume single-use temp access for this cell
        _grantedCells.remove(cellRef);
      });
      if (_currentSheet != null) {
        SocketService.instance.cellBlur(_currentSheet!.id, cellRef);
        // ── Real-time broadcast: push the new value to all other users immediately ──
        if (changed) {
          SocketService.instance.cellUpdate(
            _currentSheet!.id,
            savedRow,
            colName,
            newValue,
          );
        }
      }
      if (_isInventoryTrackerSheet() &&
          _isInventoryTotalsInputColumn(colName)) {
        _recalcInventoryTotalsForRow(savedRow);
      }
      if (changed) _markDirty();
    }
  }

  void _cancelEdit() {
    final cellRef = (_editingRow != null && _editingCol != null)
        ? _getCellReference(_editingRow!, _editingCol!)
        : null;
    setState(() {
      _editingRow = null;
      _editingCol = null;
    });
    if (cellRef != null && _currentSheet != null) {
      SocketService.instance.cellBlur(_currentSheet!.id, cellRef);
    }
  }

  // =============== Excel-like Selection Helpers ===============

  List<Map<String, String>> _cloneDataRows(List<Map<String, String>> rows) {
    return rows.map((r) => Map<String, String>.from(r)).toList();
  }

  _SheetSnapshot _captureSheetSnapshot() {
    return _SheetSnapshot(
      columns: List<String>.from(_columns),
      data: _cloneDataRows(_data),
      rowLabels: List<String>.from(_rowLabels),
      selectedRow: _selectedRow,
      selectedCol: _selectedCol,
      selectionEndRow: _selectionEndRow,
      selectionEndCol: _selectionEndCol,
    );
  }

  void _clearHistory() {
    _undoStack.clear();
    _redoStack.clear();
  }

  bool get _canUndo => _undoStack.isNotEmpty;
  bool get _canRedo => _redoStack.isNotEmpty;

  void _pushUndoSnapshot() {
    if (_isRestoringHistory) return;
    _undoStack.add(_captureSheetSnapshot());
    if (_undoStack.length > _maxHistoryEntries) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _restoreSnapshot(_SheetSnapshot snapshot) {
    setState(() {
      _columns = List<String>.from(snapshot.columns);
      _data = _cloneDataRows(snapshot.data);
      _rowLabels = List<String>.from(snapshot.rowLabels);
      _selectedRow = snapshot.selectedRow;
      _selectedCol = snapshot.selectedCol;
      _selectionEndRow = snapshot.selectionEndRow;
      _selectionEndCol = snapshot.selectionEndCol;
      _editingRow = null;
      _editingCol = null;
      _updateFormulaBar();
    });
  }

  void _undo() {
    if (!_canUndo) return;
    final current = _captureSheetSnapshot();
    final previous = _undoStack.removeLast();
    _isRestoringHistory = true;
    _redoStack.add(current);
    _restoreSnapshot(previous);
    _isRestoringHistory = false;
    _markDirty();
  }

  void _redo() {
    if (!_canRedo) return;
    final current = _captureSheetSnapshot();
    final next = _redoStack.removeLast();
    _isRestoringHistory = true;
    _undoStack.add(current);
    _restoreSnapshot(next);
    _isRestoringHistory = false;
    _markDirty();
  }

  /// Get column width for a given column index
  double _getColumnWidth(int colIndex) {
    return _columnWidths[colIndex] ?? _defaultCellWidth;
  }

  /// Get row height for a given row index
  double _getRowHeight(int rowIndex) {
    if (_collapsedRows.contains(rowIndex)) {
      return _collapsedRowHeight;
    }
    return _rowHeights[rowIndex] ?? _cellHeight;
  }

  /// Toggle row collapse/expand state
  void _toggleRowCollapse(int rowIndex) {
    setState(() {
      if (_collapsedRows.contains(rowIndex)) {
        _collapsedRows.remove(rowIndex);
      } else {
        _collapsedRows.add(rowIndex);
        // Clear selection if the collapsed row was selected
        if (_selectedRow == rowIndex) {
          _selectedRow = null;
          _selectedCol = null;
          _selectionEndRow = null;
          _selectionEndCol = null;
        }
      }
    });
  }

  // ignore: unused_element
  void _expandAllRows() {
    setState(() {
      _collapsedRows.clear();
    });
  }

  // ignore: unused_element
  void _collapseAllRows() {
    setState(() {
      for (int i = 0; i < _data.length; i++) {
        _collapsedRows.add(i);
      }
      // Clear selection
      _selectedRow = null;
      _selectedCol = null;
      _selectionEndRow = null;
      _selectionEndCol = null;
    });
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
    return row >= bounds['minRow']! &&
        row <= bounds['maxRow']! &&
        col >= bounds['minCol']! &&
        col <= bounds['maxCol']!;
  }

  /// Check if there's a multi-cell selection (more than 1 cell)
  bool get _hasMultiSelection {
    if (_selectedRow == null || _selectedCol == null) return false;
    if (_selectionEndRow == null && _selectionEndCol == null) return false;
    return _selectionEndRow != _selectedRow || _selectionEndCol != _selectedCol;
  }

  /// Select a single cell and clear range
  void _selectCell(int row, int col) {
    if (_selectedRow == row &&
        _selectedCol == col &&
        _selectionEndRow == row &&
        _selectionEndCol == col) {
      return;
    }
    setState(() {
      _selectedRow = row;
      _selectedCol = col;
      _selectionEndRow = row;
      _selectionEndCol = col;
      _updateFormulaBar();
    });
  }

  /// Extend current selection range to a new endpoint.
  void _extendSelectionTo(int row, int col) {
    if (_selectedRow == null || _selectedCol == null) {
      _selectCell(row, col);
      return;
    }
    if (_selectionEndRow == row && _selectionEndCol == col) {
      return;
    }
    setState(() {
      _selectionEndRow = row;
      _selectionEndCol = col;
      _updateFormulaBar();
    });
  }

  /// Update formula bar to show the active cell's content
  void _updateFormulaBar() {
    if (_selectedRow != null && _selectedCol != null) {
      final value = _data[_selectedRow!][_columns[_selectedCol!]] ?? '';
      _formulaBarController.text = value; // shows raw formula or plain value
    } else {
      _formulaBarController.text = '';
    }
  }

  // ─────────────────────────────────────────────────────────
  //  Excel-style Formula Evaluator
  // ─────────────────────────────────────────────────────────
  /// Evaluate a formula string (must start with '=').
  /// Returns the computed display value, or '#ERR' on failure.
  String _evaluateFormula(String formula) {
    if (!formula.startsWith('=')) return formula;
    try {
      String expr = formula.substring(1).trim().toUpperCase();

      // Handle named functions: SUM / AVERAGE / MAX / MIN / COUNT
      final funcMatch =
          RegExp(r'^(SUM|AVERAGE|AVG|MAX|MIN|COUNT)\((.+)\)$').firstMatch(expr);
      if (funcMatch != null) {
        final func = funcMatch.group(1)!;
        final values = _formulaArgValues(funcMatch.group(2)!);
        if (values.isEmpty) return '0';
        switch (func) {
          case 'SUM':
            return _fmtNum(values.fold<double>(0, (a, b) => a + b));
          case 'AVERAGE':
          case 'AVG':
            return _fmtNum(
                values.fold<double>(0, (a, b) => a + b) / values.length);
          case 'MAX':
            return _fmtNum(values.reduce((a, b) => a > b ? a : b));
          case 'MIN':
            return _fmtNum(values.reduce((a, b) => a < b ? a : b));
          case 'COUNT':
            return values.length.toString();
        }
      }

      // Replace cell refs like A1, B2 with their numeric values
      expr = expr.replaceAllMapped(
        RegExp(r'([A-Z]+)(\d+)'),
        (m) {
          final col = _excelColToIndex(m.group(1)!);
          final row = int.parse(m.group(2)!) - 1;
          return _cellRawNum(row, col);
        },
      );

      return _fmtNum(_evalExpr(expr));
    } catch (_) {
      return '#ERR';
    }
  }

  /// Resolve comma- or range-separated args into a flat list of doubles.
  List<double> _formulaArgValues(String args) {
    final values = <double>[];
    // Range: A1:B3
    final rangeMatch =
        RegExp(r'^([A-Z]+)(\d+):([A-Z]+)(\d+)$').firstMatch(args.trim());
    if (rangeMatch != null) {
      final c1 = _excelColToIndex(rangeMatch.group(1)!);
      final r1 = int.parse(rangeMatch.group(2)!) - 1;
      final c2 = _excelColToIndex(rangeMatch.group(3)!);
      final r2 = int.parse(rangeMatch.group(4)!) - 1;
      for (int r = r1; r <= r2 && r < _data.length; r++) {
        for (int c = c1; c <= c2 && c < _columns.length; c++) {
          final v = double.tryParse(_cellRawNum(r, c));
          if (v != null) values.add(v);
        }
      }
      return values;
    }
    // Comma-separated: A1,B2,C3
    for (final part in args.split(',')) {
      final cellMatch = RegExp(r'^([A-Z]+)(\d+)$', caseSensitive: false)
          .firstMatch(part.trim());
      if (cellMatch != null) {
        final col = _excelColToIndex(cellMatch.group(1)!.toUpperCase());
        final row = int.parse(cellMatch.group(2)!) - 1;
        final v = double.tryParse(_cellRawNum(row, col));
        if (v != null) values.add(v);
      }
    }
    return values;
  }

  /// Returns the raw numeric string of a cell (evaluated if formula, '0' if empty).
  String _cellRawNum(int row, int col) {
    if (row < 0 || row >= _data.length || col < 0 || col >= _columns.length) {
      return '0';
    }
    final raw = _data[row][_columns[col]] ?? '';
    if (raw.isEmpty) return '0';
    if (raw.startsWith('=')) {
      // Avoid circular reference by returning 0 for nested formulas
      return '0';
    }
    return raw;
  }

  /// Convert Excel column letter(s) to 0-based index (A→0, B→1, Z→25, AA→26).
  int _excelColToIndex(String letters) {
    int result = 0;
    for (int i = 0; i < letters.length; i++) {
      result = result * 26 + (letters.codeUnitAt(i) - 65 + 1);
    }
    return result - 1;
  }

  /// Simple recursive-descent arithmetic evaluator (+, -, *, /).
  double _evalExpr(String expr) {
    expr = expr.trim();
    while (expr.startsWith('(') && expr.endsWith(')')) {
      expr = expr.substring(1, expr.length - 1).trim();
    }
    // Scan right-to-left for lowest precedence (+/-) to handle left-associativity
    int depth = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final c = expr[i];
      if (c == ')') {
        depth++;
      } else if (c == '(') {
        depth--;
      } else if (depth == 0 && (c == '+' || c == '-') && i > 0) {
        final left = _evalExpr(expr.substring(0, i));
        final right = _evalExpr(expr.substring(i + 1));
        return c == '+' ? left + right : left - right;
      }
    }
    // Scan right-to-left for * and /
    depth = 0;
    for (int i = expr.length - 1; i >= 0; i--) {
      final c = expr[i];
      if (c == ')') {
        depth++;
      } else if (c == '(') {
        depth--;
      } else if (depth == 0 && (c == '*' || c == '/')) {
        final left = _evalExpr(expr.substring(0, i));
        final right = _evalExpr(expr.substring(i + 1));
        return c == '*'
            ? left * right
            : (right != 0 ? left / right : double.nan);
      }
    }
    return double.parse(expr);
  }

  String _fmtNum(double n) {
    if (n.isNaN || n.isInfinite) return '#ERR';
    return n % 1 == 0 ? n.toInt().toString() : n.toStringAsFixed(2);
  }

  /// Check if current user can edit the sheet (not locked by another user)
  bool _canEditSheet() {
    if (widget.readOnly) return false;
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final role = authProvider.user?.role ?? '';
    if (role == 'viewer') return false;
    if (_isLocked &&
        _lockedByUser != null &&
        _lockedByUser != authProvider.user?.username &&
        role != 'admin') {
      return false;
    }
    return true;
  }

  /// Clear selection of all selected cells (Delete key)
  void _clearSelectedCells() {
    if (!_canEditSheet()) return;

    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _data[r][_columns[c]] = '';
        }
      }
      _updateFormulaBar();
    });
    _markDirty();
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

    // Find row (accounting for collapsed rows with variable heights)
    int row = -1;
    double accY = 0;
    for (int r = 0; r < _data.length; r++) {
      final h = _getRowHeight(r);
      if (y >= accY && y < accY + h) {
        row = r;
        break;
      }
      accY += h;
    }
    if (row == -1 || row >= _data.length) return null;

    return {'row': row, 'col': col};
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    // Undo / Redo shortcuts (global in sheet view)
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _redo();
      } else {
        _undo();
      }
      return KeyEventResult.handled;
    }
    if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }

    if (_editingRow != null && _editingCol != null) {
      // In editing mode
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        _cancelEdit();
        _spreadsheetFocusNode.requestFocus();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.enter) {
        final row = _editingRow!;
        final col = _editingCol!;
        _saveEdit();
        // Move to next row
        if (row < _data.length - 1) {
          _selectCell(row + 1, col);
        }
        _spreadsheetFocusNode.requestFocus();
        return KeyEventResult.handled;
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
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
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
        return KeyEventResult.handled;
      }

      // Ctrl+C: Copy selected cells
      if (isCtrl && event.logicalKey == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }

      if (event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.f2) {
        _startEditing(_selectedRow!, _selectedCol!);
        return KeyEventResult.handled;
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
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (isShift) {
          final endRow = (_selectionEndRow ?? _selectedRow!) + 1;
          if (endRow < _data.length) {
            setState(() => _selectionEndRow = endRow);
          }
        } else if (_selectedRow! < _data.length - 1) {
          _selectCell(_selectedRow! + 1, _selectedCol!);
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        if (isShift) {
          final endCol = (_selectionEndCol ?? _selectedCol!) - 1;
          if (endCol >= 0) {
            setState(() => _selectionEndCol = endCol);
          }
        } else if (_selectedCol! > 0) {
          _selectCell(_selectedRow!, _selectedCol! - 1);
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        if (isShift) {
          final endCol = (_selectionEndCol ?? _selectedCol!) + 1;
          if (endCol < _columns.length) {
            setState(() => _selectionEndCol = endCol);
          }
        } else if (_selectedCol! < _columns.length - 1) {
          _selectCell(_selectedRow!, _selectedCol! + 1);
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.tab) {
        if (_selectedCol! < _columns.length - 1) {
          _selectCell(_selectedRow!, _selectedCol! + 1);
        } else if (_selectedRow! < _data.length - 1) {
          _selectCell(_selectedRow! + 1, 0);
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.delete ||
          event.logicalKey == LogicalKeyboardKey.backspace) {
        _clearSelectedCells();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        if (isCtrl) {
          _selectCell(0, 0);
        } else {
          _selectCell(_selectedRow!, 0);
        }
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.end) {
        if (isCtrl) {
          _selectCell(_data.length - 1, _columns.length - 1);
        } else {
          _selectCell(_selectedRow!, _columns.length - 1);
        }
        return KeyEventResult.handled;
      } else {
        // Start editing on any printable key press
        final key = event.character;
        if (key != null && key.length == 1 && !isCtrl) {
          _startEditing(_selectedRow!, _selectedCol!);
          _editController.text = key;
          _editController.selection =
              TextSelection.collapsed(offset: key.length);
          return KeyEventResult.handled;
        }
      }
      return KeyEventResult.ignored;
    }

    return KeyEventResult.ignored;
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
    _autoSaveTimer?.cancel(); // stop pending auto-save
    if (_currentSheet != null) {
      SocketService.instance.leaveSheet(_currentSheet!.id);
    }
    SocketService.instance.clearCallbacks();
    _editController.dispose();
    _formulaBarController.dispose();
    _inventorySearchController.dispose();
    _focusNode.dispose();
    _formulaBarFocusNode.dispose();
    _spreadsheetFocusNode.dispose();
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    _headerHScrollController.dispose();
    _rowNumVScrollController.dispose();
    super.dispose();
  }

  // ─── Theme colors (Grey background palette) ───
  static const Color _kContentBg = AppColors.bgLight; // light grey background
  static const Color _kNavy = Color(0xFF1F2937); // neutral dark text
  static const Color _kBlue = Color(0xFF4285F4); // blue accent
  static const Color _kGreen = Color(0xFF22C55E); // action green
  static const Color _kGray = Color(0xFF6B7280);
  static const Color _kBorder = Color(0xFFE5E7EB);
  static const Color _kBg = Color(0xFFF9FAFB);

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _pageBgColor => _isDark ? const Color(0xFF0B1220) : _kContentBg;
  Color get _surfaceColor => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _surfaceAltColor => _isDark ? const Color(0xFF0F172A) : _kBg;
  Color get _borderColor => _isDark ? const Color(0xFF334155) : _kBorder;
  Color get _textPrimary => _isDark ? const Color(0xFFE5E7EB) : _kNavy;
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : _kGray;

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthProvider>(
      builder: (context, auth, _) {
        final role = auth.user?.role ?? '';
        final isViewer = role == 'viewer';

        // If a sheet is opened, show the spreadsheet editor
        if (_currentSheet != null) {
          return Scaffold(
            backgroundColor: _pageBgColor,
            body: Column(
              children: [
                // ── Sheet name bar (back btn • name • search • presence) ──
                _buildSheetNameBar(),
                // ── Ribbon toolbar ──
                _buildRibbonToolbar(),
                // ── Formula bar ──
                _buildFormulaBar(),
                // ── Spreadsheet grid ──
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _isInventoryTrackerSheet()
                          ? _buildInventoryTrackerGrid()
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
          backgroundColor: _pageBgColor,
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
    final isAtRoot = _currentSheetFolderId == null;

    final sortedSheets = List<SheetModel>.from(_sheets)
      ..sort((a, b) {
        final aDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
        final bDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
        return bDate.compareTo(aDate);
      });

    final recentSheets = sortedSheets.take(6).toList();

    const cardRadius = 16.0;
    final cardShadow = BoxShadow(
      color: Colors.black.withOpacity(0.04),
      blurRadius: 14,
      offset: const Offset(0, 4),
    );
    final hoverShadow = BoxShadow(
      color: Colors.black.withOpacity(0.07),
      blurRadius: 18,
      offset: const Offset(0, 6),
    );

    Widget sectionCard({
      required Widget child,
      EdgeInsets padding = const EdgeInsets.all(18),
    }) {
      return Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(cardRadius),
          border: Border.all(color: _borderColor),
          boxShadow: [cardShadow],
        ),
        child: child,
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header card (title/breadcrumbs + actions) ──
                sectionCard(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            if (!isAtRoot) ...[
                              InkWell(
                                onTap: _navigateToSheetRoot,
                                borderRadius: BorderRadius.circular(10),
                                child: Row(
                                  children: [
                                    Icon(Icons.home_outlined,
                                        size: 20, color: _textPrimary),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Home',
                                      style: TextStyle(
                                        fontSize: 16,
                                        color: _textPrimary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ..._sheetFolderBreadcrumbs
                                  .asMap()
                                  .entries
                                  .skip(1)
                                  .map((entry) {
                                final idx = entry.key;
                                final crumb = entry.value;
                                return Row(
                                  children: [
                                    Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 6),
                                      child: Icon(Icons.chevron_right,
                                          size: 18, color: _textSecondary),
                                    ),
                                    InkWell(
                                      onTap: () =>
                                          _navigateToSheetBreadcrumb(idx),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Text(
                                          crumb['name'] ?? '',
                                          style: TextStyle(
                                              fontSize: 15,
                                              color: _textPrimary),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }),
                              Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.chevron_right,
                                    size: 18, color: _textSecondary),
                              ),
                              Text(
                                _currentSheetFolderName ?? '',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _textPrimary,
                                ),
                              ),
                            ] else
                              const SizedBox.shrink(),
                          ],
                        ),
                      ),
                      if (!isViewer) ...[
                        const SizedBox(width: 14),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          alignment: WrapAlignment.end,
                          children: [
                            _buildOutlinedBtn(
                              icon: Icons.create_new_folder_outlined,
                              label: 'New Folder',
                              onPressed: _showCreateFolderDialog,
                            ),
                            _buildOutlinedBtn(
                              icon: Icons.upload_file,
                              label: 'Import Excel',
                              onPressed: _importSheet,
                            ),
                            OutlinedButton.icon(
                              onPressed: _showTemplatePickerDialog,
                              icon: const Icon(
                                  Icons.dashboard_customize_outlined,
                                  size: 18),
                              label: const Text('Template'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _kGreen,
                                side: const BorderSide(
                                    color: _kGreen, width: 1.2),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                backgroundColor: _surfaceColor,
                              ),
                            ),
                            ElevatedButton.icon(
                              onPressed: _createNewSheet,
                              icon: const Icon(Icons.add, size: 18),
                              label: const Text('New Sheet'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kGreen,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 18, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Folders section ──
                sectionCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Folders',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _textPrimary,
                        ),
                      ),
                      const SizedBox(height: 14),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 260,
                          mainAxisExtent: 80,
                          crossAxisSpacing: 14,
                          mainAxisSpacing: 14,
                        ),
                        itemCount: _sheetFolders.length,
                        itemBuilder: (context, i) {
                          final folder = _sheetFolders[i];
                          final folderId = (folder['id'] is num)
                              ? (folder['id'] as num).toInt()
                              : (int.tryParse('${folder['id'] ?? ''}') ?? i);
                          final isHovered = _hoveredFolderId == folderId;
                          final folderRole = auth.user?.role ?? '';
                          final canManageFolder = folderRole == 'admin' ||
                              folderRole == 'editor' ||
                              folderRole == 'manager';
                          final canDeleteFolder =
                              folderRole == 'admin' || folderRole == 'manager';
                          final folderHasPassword =
                              folder['has_password'] == true;

                          return MouseRegion(
                            onEnter: (_) =>
                                setState(() => _hoveredFolderId = folderId),
                            onExit: (_) =>
                                setState(() => _hoveredFolderId = null),
                            child: Stack(
                              children: [
                                InkWell(
                                  onTap: () =>
                                      _openFolderWithPasswordCheck(folder),
                                  borderRadius:
                                      BorderRadius.circular(cardRadius),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 140),
                                    padding: const EdgeInsets.fromLTRB(
                                        14, 12, 34, 12),
                                    decoration: BoxDecoration(
                                      color: isHovered
                                          ? _surfaceAltColor
                                          : _surfaceColor,
                                      borderRadius:
                                          BorderRadius.circular(cardRadius),
                                      border: Border.all(
                                        color: isHovered
                                            ? _kBlue.withOpacity(0.35)
                                            : _borderColor,
                                      ),
                                      boxShadow: isHovered
                                          ? [hoverShadow]
                                          : [cardShadow],
                                    ),
                                    child: Row(
                                      children: [
                                        Stack(
                                          children: [
                                            Icon(Icons.folder,
                                                color: Colors.amber[700],
                                                size: 30),
                                            if (folderHasPassword)
                                              Positioned(
                                                right: 0,
                                                bottom: 0,
                                                child: Container(
                                                  width: 14,
                                                  height: 14,
                                                  decoration: BoxDecoration(
                                                      color: Colors.orange[700],
                                                      shape: BoxShape.circle),
                                                  child: const Icon(Icons.lock,
                                                      size: 10,
                                                      color: Colors.white),
                                                ),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                folder['name'] ?? '',
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                  color: _textPrimary,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${folder['sheet_count'] ?? 0} sheets',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: _textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (canManageFolder)
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: PopupMenuButton<String>(
                                      icon: Icon(Icons.more_horiz,
                                          size: 18, color: _textSecondary),
                                      padding: EdgeInsets.zero,
                                      iconSize: 18,
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _confirmDeleteFolder(folder);
                                        }
                                        if (value == 'set_password') {
                                          _setFolderPassword(folder);
                                        }
                                      },
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'set_password',
                                          child: Row(
                                            children: [
                                              Icon(Icons.lock_outline,
                                                  size: 16,
                                                  color: folderHasPassword
                                                      ? Colors.orange
                                                      : Colors.grey[600]),
                                              const SizedBox(width: 8),
                                              Text(folderHasPassword
                                                  ? 'Change Password'
                                                  : 'Set Password'),
                                            ],
                                          ),
                                        ),
                                        if (canDeleteFolder)
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline,
                                                    size: 16,
                                                    color: Colors.red),
                                                SizedBox(width: 8),
                                                Text('Delete Folder',
                                                    style: TextStyle(
                                                        color: Colors.red)),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── Recent section ──
                if (recentSheets.isNotEmpty) ...[
                  sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Sheets',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 128,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: recentSheets.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 14),
                            itemBuilder: (context, index) {
                              final sheet = recentSheets[index];
                              return _buildRecentCard(sheet);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── All sheets section ──
                sectionCard(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            isAtRoot
                                ? 'All Sheets'
                                : 'Sheets in "$_currentSheetFolderName"',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: _textPrimary,
                            ),
                          ),
                          const Spacer(),
                          if (_selectedSheetIds.isNotEmpty) ...[
                            Text(
                              '${_selectedSheetIds.length} selected',
                              style: TextStyle(
                                fontSize: 12,
                                color: _textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              onPressed: (auth.user?.role == 'admin' ||
                                      auth.user?.role == 'manager' ||
                                      auth.user?.role == 'editor')
                                  ? _bulkMoveSheets
                                  : null,
                              icon: const Icon(Icons.drive_file_move_outlined,
                                  size: 14),
                              label: const Text('Move',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _textSecondary,
                                side: BorderSide(color: _borderColor),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            OutlinedButton.icon(
                              onPressed: auth.user?.role == 'admin'
                                  ? _bulkDeleteSheets
                                  : null,
                              icon: const Icon(Icons.delete_outline, size: 14),
                              label: const Text('Delete',
                                  style: TextStyle(fontSize: 12)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            TextButton(
                              onPressed: () =>
                                  setState(() => _selectedSheetIds.clear()),
                              style: TextButton.styleFrom(
                                foregroundColor: _textSecondary,
                              ),
                              child: const Text('Clear',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (_sheets.isEmpty && _sheetFolders.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 44),
                          decoration: BoxDecoration(
                            color: _surfaceAltColor,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _borderColor),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.description_outlined,
                                  size: 46,
                                  color: _isDark
                                      ? const Color(0xFF334155)
                                      : Colors.grey[300]),
                              const SizedBox(height: 12),
                              Text(
                                isViewer
                                    ? 'No sheets shared with you yet'
                                    : 'No sheets yet — create one!',
                                style: TextStyle(
                                    color: _textSecondary, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      else
                        _buildAllSheetsTable(auth),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DateTime? _tryParseApiDate(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v;
    return DateTime.tryParse(v.toString());
  }

  Future<void> _toggleExplorerFolder(Map<String, dynamic> folder) async {
    final folderId = (folder['id'] is int)
        ? folder['id'] as int
        : int.tryParse(folder['id']?.toString() ?? '');
    if (folderId == null) return;

    final isExpanded = _explorerExpandedFolderIds.contains(folderId);
    if (isExpanded) {
      setState(() => _explorerExpandedFolderIds.remove(folderId));
      return;
    }

    setState(() => _explorerExpandedFolderIds.add(folderId));

    // Lazy-load children (folders + sheets) for this folder without changing
    // the current navigation context.
    if (_explorerFolderCache.containsKey(folderId) ||
        _explorerLoadingFolderIds.contains(folderId)) {
      return;
    }

    setState(() => _explorerLoadingFolderIds.add(folderId));
    try {
      final response = await ApiService.getSheets(folderId: folderId);
      if (!mounted) return;

      final childSheets = (response['sheets'] as List?)
              ?.map((s) => SheetModel.fromJson(s))
              .toList() ??
          <SheetModel>[];
      final childFolders = (response['folders'] as List?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          <Map<String, dynamic>>[];

      // If the user collapsed quickly, don't bother updating the UI further.
      if (!_explorerExpandedFolderIds.contains(folderId)) return;

      setState(() {
        _explorerFolderCache[folderId] = _ExplorerFolderContents(
          folders: childFolders,
          sheets: childSheets,
        );
      });
    } catch (_) {
      // Keep it silent; the folder just won't expand.
    } finally {
      if (mounted) {
        setState(() => _explorerLoadingFolderIds.remove(folderId));
      }
    }
  }

  Future<void> _ensureExplorerFolderLoaded(
    int folderId, {
    bool forceRefresh = false,
  }) async {
    if (_explorerLoadingFolderIds.contains(folderId)) return;
    if (!forceRefresh && _explorerFolderCache.containsKey(folderId)) return;

    if (!mounted) return;
    setState(() => _explorerLoadingFolderIds.add(folderId));
    try {
      final response = await ApiService.getSheets(folderId: folderId);
      if (!mounted) return;

      final childSheets = (response['sheets'] as List?)
              ?.map((s) => SheetModel.fromJson(s))
              .toList() ??
          <SheetModel>[];
      final childFolders = (response['folders'] as List?)
              ?.cast<Map<String, dynamic>>()
              .toList() ??
          <Map<String, dynamic>>[];

      setState(() {
        _explorerFolderCache[folderId] = _ExplorerFolderContents(
          folders: childFolders,
          sheets: childSheets,
        );
      });
    } catch (_) {
      // Keep it silent; the folder just won't show children.
    } finally {
      if (mounted) {
        setState(() => _explorerLoadingFolderIds.remove(folderId));
      }
    }
  }

  // ── Recent sheet card ──
  Widget _buildRecentCard(SheetModel sheet) {
    final timeAgo = _timeAgo(sheet.updatedAt ?? sheet.createdAt);
    final isHovered = _hoveredRecentSheetId == sheet.id;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRecentSheetId = sheet.id),
      onExit: (_) => setState(() => _hoveredRecentSheetId = null),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openSheetWithPasswordCheck(sheet),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: 190,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: isHovered ? _surfaceAltColor : _surfaceColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isHovered ? _kBlue.withOpacity(0.35) : _borderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isHovered ? 0.07 : 0.04),
                blurRadius: isHovered ? 18 : 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _kGreen,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.description_outlined,
                            color: Colors.white, size: 18),
                      ),
                      const Spacer(),
                      PopupMenuButton<String>(
                        tooltip: 'Actions',
                        icon: Icon(Icons.more_horiz,
                            size: 18, color: _textSecondary),
                        padding: EdgeInsets.zero,
                        onSelected: (value) {
                          if (value == 'open') {
                            _openSheetWithPasswordCheck(sheet);
                          }
                          if (value == 'rename') {
                            _renameSheet(sheet);
                          }
                          if (value == 'move') {
                            _showMoveSheetToFolderDialog(sheet);
                          }
                          if (value == 'set_password') {
                            _setSheetPassword(sheet);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'open',
                            child: Text('Open'),
                          ),
                          const PopupMenuItem(
                            value: 'rename',
                            child: Text('Rename'),
                          ),
                          const PopupMenuItem(
                            value: 'move',
                            child: Text('Move to Folder'),
                          ),
                          PopupMenuItem(
                            value: 'set_password',
                            child: Row(
                              children: [
                                Icon(Icons.lock_outline,
                                    size: 16,
                                    color: sheet.hasPassword
                                        ? Colors.orange
                                        : Colors.grey[600]),
                                const SizedBox(width: 8),
                                Text(sheet.hasPassword
                                    ? 'Change Password'
                                    : 'Set Password'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    sheet.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Last modified · $timeAgo',
                    style: TextStyle(fontSize: 11, color: _textSecondary),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── All Sheets data table ──
  Widget _buildAllSheetsTable(AuthProvider auth) {
    final role = auth.user?.role ?? '';
    final canManage = role == 'admin' || role == 'editor' || role == 'manager';
    final canManageFolders = canManage;
    final canDeleteFolder = role == 'admin';

    List<Map<String, dynamic>> sortFolders(List<Map<String, dynamic>> folders) {
      final copy = List<Map<String, dynamic>>.from(folders);
      copy.sort((a, b) {
        final an = (a['name']?.toString() ?? '').toLowerCase();
        final bn = (b['name']?.toString() ?? '').toLowerCase();
        return an.compareTo(bn);
      });
      return copy;
    }

    List<_ExplorerEntry> buildEntries({
      required List<Map<String, dynamic>> folders,
      required List<SheetModel> sheets,
      required int depth,
    }) {
      final entries = <_ExplorerEntry>[];

      for (final folder in sortFolders(folders)) {
        final folderId = (folder['id'] is int)
            ? folder['id'] as int
            : int.tryParse(folder['id']?.toString() ?? '') ?? -1;
        final expanded = _explorerExpandedFolderIds.contains(folderId);
        final loading = _explorerLoadingFolderIds.contains(folderId);
        entries.add(_ExplorerEntry.folder(
          folder: folder,
          depth: depth,
          isExpanded: expanded,
          isLoading: loading,
        ));

        if (expanded) {
          final cached = _explorerFolderCache[folderId];
          if (loading || cached == null) {
            entries.add(_ExplorerEntry.loading(depth: depth + 1));
          } else {
            if (cached.folders.isEmpty && cached.sheets.isEmpty) {
              entries.add(_ExplorerEntry.emptyFolder(depth: depth + 1));
            }
            entries.addAll(buildEntries(
              folders: cached.folders,
              sheets: cached.sheets,
              depth: depth + 1,
            ));
          }
        }
      }

      // Keep the sheet order as returned by the API (updated desc)
      for (final sheet in sheets) {
        entries.add(_ExplorerEntry.sheet(sheet: sheet, depth: depth));
      }

      return entries;
    }

    final entries = buildEntries(
      folders: _sheetFolders,
      sheets: _sheets,
      depth: 0,
    );

    final visibleSheetIds = entries
        .where((e) => e.kind == _ExplorerEntryKind.sheet)
        .map((e) => e.sheet!.id)
        .toList(growable: false);

    final allSelected = visibleSheetIds.isNotEmpty &&
        visibleSheetIds.every((id) => _selectedSheetIds.contains(id));
    final anySelected =
        visibleSheetIds.any((id) => _selectedSheetIds.contains(id));
    final headerTristate = anySelected && !allSelected;

    Widget hoverWrap(int idx, Widget child) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hoveredAllSheetsRowIndex = idx),
        onExit: (_) => setState(() => _hoveredAllSheetsRowIndex = null),
        child: child,
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const checkboxW = 48.0;
            const actionsW = 90.0;
            const totalFlex = 3.0 + 1.5 + 1.4 + 1.4;
            final remaining = (constraints.maxWidth - checkboxW - actionsW)
                .clamp(240.0, double.infinity);
            final nameW = remaining * (3.0 / totalFlex);
            final ownerW = remaining * (1.5 / totalFlex);
            final createdW = remaining * (1.4 / totalFlex);
            final modifiedW = remaining * (1.4 / totalFlex);

            Widget headerCell(String label) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: _textSecondary,
                  ),
                ),
              );
            }

            Widget indentGuides(int depth) {
              if (depth <= 0) return const SizedBox.shrink();
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(depth, (i) {
                  return SizedBox(
                    width: 16,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 1,
                        height: 36,
                        color: _borderColor.withOpacity(_isDark ? 0.55 : 0.85),
                      ),
                    ),
                  );
                }),
              );
            }

            Widget nameCellFolder({
              required Map<String, dynamic> folder,
              required int depth,
              required bool isExpanded,
              required bool isLoading,
            }) {
              final folderName = folder['name']?.toString() ?? 'Folder';

              return InkWell(
                onTap: () => _toggleExplorerFolder(folder),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      indentGuides(depth),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _kBlue.withOpacity(_isDark ? 0.35 : 0.18),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Icon(
                            isExpanded
                                ? Icons.folder_open_rounded
                                : Icons.folder_rounded,
                            color: _isDark ? const Color(0xFFBFDBFE) : _kBlue,
                            size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                folderName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                            if (isLoading) ...[
                              const SizedBox(width: 10),
                              SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      _textSecondary),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget nameCellSheet({
              required SheetModel sheet,
              required int depth,
            }) {
              return InkWell(
                onTap: () => _openSheetWithPasswordCheck(sheet),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  child: Row(
                    children: [
                      indentGuides(depth),
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: _kGreen,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: Colors.white,
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                sheet.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: _textPrimary,
                                ),
                              ),
                            ),
                            if (sheet.hasPassword) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.lock,
                                  size: 13, color: Colors.orange[700]),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }

            Widget cellText(String text, {VoidCallback? onTap}) {
              final content = Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
              );
              if (onTap == null) return content;
              return Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, child: content),
              );
            }

            final rowHeight = 52.0;
            final bodyHeight = 520.0;

            return Column(
              children: [
                // Header row
                Container(
                  color: _surfaceAltColor,
                  child: Row(
                    children: [
                      SizedBox(
                        width: checkboxW,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Checkbox(
                            value: allSelected,
                            tristate: headerTristate,
                            onChanged: canManage
                                ? (_) => setState(() {
                                      if (allSelected) {
                                        _selectedSheetIds.removeWhere((id) =>
                                            visibleSheetIds.contains(id));
                                      } else {
                                        _selectedSheetIds
                                            .addAll(visibleSheetIds);
                                      }
                                    })
                                : null,
                          ),
                        ),
                      ),
                      SizedBox(width: nameW, child: headerCell('Name')),
                      SizedBox(width: ownerW, child: headerCell('Owner')),
                      SizedBox(width: createdW, child: headerCell('Created')),
                      SizedBox(
                          width: modifiedW, child: headerCell('Last Modified')),
                      SizedBox(width: actionsW, child: headerCell('Actions')),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: _borderColor),
                SizedBox(
                  height: bodyHeight,
                  child: ListView.builder(
                    itemCount: entries.length,
                    itemExtent: rowHeight,
                    itemBuilder: (context, idx) {
                      final entry = entries[idx];
                      final isHovered = _hoveredAllSheetsRowIndex == idx;

                      final baseAlt = idx.isEven
                          ? _surfaceColor
                          : _surfaceAltColor.withOpacity(0.7);

                      Color rowBg = isHovered ? _surfaceAltColor : baseAlt;

                      if (entry.kind == _ExplorerEntryKind.folder) {
                        final folderId = (entry.folder?['id'] is int)
                            ? entry.folder!['id'] as int
                            : int.tryParse(
                                entry.folder?['id']?.toString() ?? '');
                        final isFolderSelected = folderId != null &&
                            _explorerSelectedFolderIds.contains(folderId);
                        if (isFolderSelected) {
                          rowBg = _kBlue.withOpacity(0.10);
                        }
                        if (entry.isExpanded == true) {
                          rowBg = _kBlue.withOpacity(0.06);
                        }
                      }

                      if (entry.kind == _ExplorerEntryKind.sheet) {
                        final sheet = entry.sheet!;
                        final isSelected = _selectedSheetIds.contains(sheet.id);
                        final isOpening = _openingSheetId == sheet.id;
                        final isActiveSheet = _currentSheet?.id == sheet.id;
                        rowBg = isSelected
                            ? _kBlue.withOpacity(0.10)
                            : isOpening
                                ? _kBlue.withOpacity(0.08)
                                : isActiveSheet
                                    ? _kBlue.withOpacity(0.06)
                                    : (isHovered ? _surfaceAltColor : baseAlt);
                      }

                      return hoverWrap(
                        idx,
                        Container(
                          color: rowBg,
                          child: Row(
                            children: [
                              SizedBox(
                                width: checkboxW,
                                child: () {
                                  if (entry.kind == _ExplorerEntryKind.sheet) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Checkbox(
                                        value: _selectedSheetIds
                                            .contains(entry.sheet!.id),
                                        onChanged: canManage
                                            ? (v) => setState(() {
                                                  if (v == true) {
                                                    _selectedSheetIds
                                                        .add(entry.sheet!.id);
                                                  } else {
                                                    _selectedSheetIds.remove(
                                                        entry.sheet!.id);
                                                  }
                                                })
                                            : null,
                                      ),
                                    );
                                  }

                                  if (entry.kind == _ExplorerEntryKind.folder) {
                                    final folderId = (entry.folder?['id']
                                            is int)
                                        ? entry.folder!['id'] as int
                                        : int.tryParse(
                                            entry.folder?['id']?.toString() ??
                                                '');
                                    if (folderId == null)
                                      return const SizedBox();
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Checkbox(
                                        value: _explorerSelectedFolderIds
                                            .contains(folderId),
                                        onChanged: canManageFolders
                                            ? (v) => setState(() {
                                                  if (v == true) {
                                                    _explorerSelectedFolderIds
                                                        .add(folderId);
                                                  } else {
                                                    _explorerSelectedFolderIds
                                                        .remove(folderId);
                                                  }
                                                })
                                            : null,
                                      ),
                                    );
                                  }

                                  return const SizedBox();
                                }(),
                              ),
                              SizedBox(
                                width: nameW,
                                child: () {
                                  if (entry.kind == _ExplorerEntryKind.folder) {
                                    return nameCellFolder(
                                      folder: entry.folder!,
                                      depth: entry.depth,
                                      isExpanded: entry.isExpanded ?? false,
                                      isLoading: entry.isLoading ?? false,
                                    );
                                  }
                                  if (entry.kind == _ExplorerEntryKind.sheet) {
                                    return nameCellSheet(
                                      sheet: entry.sheet!,
                                      depth: entry.depth,
                                    );
                                  }
                                  // loading/empty row
                                  final label = entry.kind ==
                                          _ExplorerEntryKind.emptyFolder
                                      ? 'Empty'
                                      : 'Loading…';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12),
                                    child: Row(
                                      children: [
                                        indentGuides(entry.depth),
                                        Icon(
                                          entry.kind ==
                                                  _ExplorerEntryKind.emptyFolder
                                              ? Icons.inbox_outlined
                                              : Icons.hourglass_empty,
                                          size: 16,
                                          color: _textSecondary,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(label,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: _textSecondary)),
                                      ],
                                    ),
                                  );
                                }(),
                              ),
                              SizedBox(
                                width: ownerW,
                                child: () {
                                  if (entry.kind == _ExplorerEntryKind.sheet) {
                                    final sheet = entry.sheet!;
                                    final isOpening =
                                        _openingSheetId == sheet.id;
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: isOpening
                                            ? null
                                            : () => _openSheetWithPasswordCheck(
                                                sheet),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 12),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              CircleAvatar(
                                                radius: 12,
                                                backgroundColor:
                                                    _surfaceAltColor,
                                                child: Icon(Icons.person,
                                                    size: 14,
                                                    color: _textSecondary),
                                              ),
                                              const SizedBox(width: 6),
                                              Text('admin',
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      color: _textSecondary)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  if (entry.kind == _ExplorerEntryKind.folder) {
                                    final owner = entry.folder?['created_by']
                                            ?.toString() ??
                                        '-';
                                    return cellText(owner);
                                  }
                                  return cellText('-');
                                }(),
                              ),
                              SizedBox(
                                width: createdW,
                                child: () {
                                  if (entry.kind == _ExplorerEntryKind.sheet) {
                                    final sheet = entry.sheet!;
                                    final isOpening =
                                        _openingSheetId == sheet.id;
                                    return cellText(
                                      _formatDate(sheet.createdAt),
                                      onTap: isOpening
                                          ? null
                                          : () => _openSheetWithPasswordCheck(
                                              sheet),
                                    );
                                  }
                                  if (entry.kind == _ExplorerEntryKind.folder) {
                                    final created = _tryParseApiDate(
                                        entry.folder?['created_at']);
                                    return cellText(_formatDate(created));
                                  }
                                  return cellText('-');
                                }(),
                              ),
                              SizedBox(
                                width: modifiedW,
                                child: () {
                                  if (entry.kind == _ExplorerEntryKind.sheet) {
                                    final sheet = entry.sheet!;
                                    final isOpening =
                                        _openingSheetId == sheet.id;
                                    return cellText(
                                      _formatDate(
                                          sheet.updatedAt ?? sheet.createdAt),
                                      onTap: isOpening
                                          ? null
                                          : () => _openSheetWithPasswordCheck(
                                              sheet),
                                    );
                                  }
                                  if (entry.kind == _ExplorerEntryKind.folder) {
                                    final updated = _tryParseApiDate(
                                        entry.folder?['updated_at']);
                                    return cellText(_formatDate(updated));
                                  }
                                  return cellText('-');
                                }(),
                              ),
                              SizedBox(
                                width: actionsW,
                                child: () {
                                  if (entry.kind != _ExplorerEntryKind.sheet) {
                                    if (entry.kind !=
                                        _ExplorerEntryKind.folder) {
                                      return const SizedBox();
                                    }

                                    final folder = entry.folder!;
                                    final folderHasPassword =
                                        folder['has_password'] == true;

                                    if (!canManageFolders && !canDeleteFolder) {
                                      return const SizedBox();
                                    }

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (canManageFolders)
                                            PopupMenuButton<String>(
                                              icon: Icon(Icons.more_horiz,
                                                  size: 18,
                                                  color: _textSecondary),
                                              padding: EdgeInsets.zero,
                                              onSelected: (value) {
                                                if (value == 'set_password') {
                                                  _setFolderPassword(folder);
                                                }
                                                if (value == 'delete') {
                                                  _confirmDeleteFolder(folder);
                                                }
                                              },
                                              itemBuilder: (_) => [
                                                PopupMenuItem(
                                                  value: 'set_password',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.lock_outline,
                                                          size: 16,
                                                          color:
                                                              folderHasPassword
                                                                  ? Colors
                                                                      .orange
                                                                  : Colors.grey[
                                                                      600]),
                                                      const SizedBox(width: 8),
                                                      Text(folderHasPassword
                                                          ? 'Change Password'
                                                          : 'Set Password'),
                                                    ],
                                                  ),
                                                ),
                                                if (canDeleteFolder)
                                                  const PopupMenuItem(
                                                    value: 'delete',
                                                    child: Row(
                                                      children: [
                                                        Icon(
                                                            Icons
                                                                .delete_outline,
                                                            size: 16,
                                                            color: Colors.red),
                                                        SizedBox(width: 8),
                                                        Text('Delete Folder',
                                                            style: TextStyle(
                                                                color: Colors
                                                                    .red)),
                                                      ],
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          if (canDeleteFolder)
                                            Tooltip(
                                              message: 'Delete folder',
                                              child: InkWell(
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                onTap: () =>
                                                    _confirmDeleteFolder(
                                                        folder),
                                                child: Padding(
                                                  padding:
                                                      const EdgeInsets.all(6),
                                                  child: Icon(
                                                      Icons.delete_outline,
                                                      size: 18,
                                                      color: Colors.red[400]),
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    );
                                  }
                                  final sheet = entry.sheet!;
                                  final isOpening = _openingSheetId == sheet.id;
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8),
                                    child: canManage
                                        ? Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              AnimatedSwitcher(
                                                duration: const Duration(
                                                    milliseconds: 160),
                                                child: isOpening
                                                    ? SizedBox(
                                                        key: ValueKey(
                                                            'opening_${sheet.id}'),
                                                        width: 18,
                                                        height: 18,
                                                        child:
                                                            CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          valueColor:
                                                              AlwaysStoppedAnimation<
                                                                      Color>(
                                                                  _textSecondary),
                                                        ),
                                                      )
                                                    : PopupMenuButton<String>(
                                                        key: ValueKey(
                                                            'menu_${sheet.id}'),
                                                        icon: Icon(
                                                            Icons.more_horiz,
                                                            size: 18,
                                                            color:
                                                                _textSecondary),
                                                        padding:
                                                            EdgeInsets.zero,
                                                        onSelected: (value) {
                                                          if (value == 'open') {
                                                            _openSheetWithPasswordCheck(
                                                                sheet);
                                                          }
                                                          if (value ==
                                                              'rename') {
                                                            _renameSheet(sheet);
                                                          }
                                                          if (value == 'move') {
                                                            _showMoveSheetToFolderDialog(
                                                                sheet);
                                                          }
                                                          if (value ==
                                                              'set_password') {
                                                            _setSheetPassword(
                                                                sheet);
                                                          }
                                                        },
                                                        itemBuilder: (_) => [
                                                          const PopupMenuItem(
                                                              value: 'open',
                                                              child:
                                                                  Text('Open')),
                                                          const PopupMenuItem(
                                                              value: 'rename',
                                                              child: Text(
                                                                  'Rename')),
                                                          const PopupMenuItem(
                                                              value: 'move',
                                                              child: Text(
                                                                  'Move to Folder')),
                                                          PopupMenuItem(
                                                            value:
                                                                'set_password',
                                                            child: Row(
                                                              children: [
                                                                Icon(
                                                                    Icons
                                                                        .lock_outline,
                                                                    size: 16,
                                                                    color: sheet.hasPassword
                                                                        ? Colors
                                                                            .orange
                                                                        : Colors
                                                                            .grey[600]),
                                                                const SizedBox(
                                                                    width: 8),
                                                                Text(sheet
                                                                        .hasPassword
                                                                    ? 'Change Password'
                                                                    : 'Set Password'),
                                                              ],
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                              ),
                                              if (role == 'admin')
                                                Tooltip(
                                                  message: 'Delete sheet',
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    onTap: isOpening
                                                        ? null
                                                        : () =>
                                                            _confirmDeleteSheet(
                                                                sheet),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                              6),
                                                      child: Icon(
                                                          Icons.delete_outline,
                                                          size: 18,
                                                          color:
                                                              Colors.red[400]),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          )
                                        : const SizedBox(),
                                  );
                                }(),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOutlinedBtn({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: _textSecondary),
      label: Text(label, style: TextStyle(color: _textPrimary, fontSize: 13)),
      style: OutlinedButton.styleFrom(
        side: BorderSide(color: _borderColor, width: 1.2),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        backgroundColor: _surfaceColor,
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
  // ignore: unused_element
  Widget _buildRedHeader() {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: Color(0xFFFAF0E6),
        border: Border(
          bottom: BorderSide(color: Color(0xFFDDD5CC), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back,
                size: 20, color: Color(0xFF6B1C1C)),
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
                _activeSheetUsers = [];
              });
            },
          ),
          const SizedBox(width: 8),
          const Text(
            'Work Sheets',
            style: TextStyle(
              color: Color(0xFF6B1C1C),
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.2,
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
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final role = authProv.user?.role ?? '';
    final isViewer = role == 'viewer';
    final currentUsername = authProv.user?.username ?? '';
    final isLockedByMe =
        _isLocked && _lockedByUser != null && _lockedByUser == currentUsername;
    final isLockedByOther =
        _isLocked && _lockedByUser != null && _lockedByUser != currentUsername;

    // ── Inline save-status chip ──────────────────────────────────────────────
    Widget saveChip() {
      switch (_saveStatus) {
        case 'saving':
          return Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 11,
                height: 11,
                child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor:
                        const AlwaysStoppedAnimation(AppColors.primaryBlue))),
            const SizedBox(width: 5),
            const Text('Saving…',
                style: TextStyle(fontSize: 11, color: AppColors.primaryBlue)),
          ]);
        case 'unsaved':
          return Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: Colors.orange[700]),
            const SizedBox(width: 4),
            Text('Unsaved changes',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w500)),
          ]);
        default:
          return Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.check_circle_outline,
                size: 13, color: Color(0xFF2D9B5A)),
            const SizedBox(width: 3),
            const Text('Saved',
                style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF2D9B5A),
                    fontWeight: FontWeight.w500)),
          ]);
      }
    }

    // ── Compact presence avatar row ──────────────────────────────────────────
    // ignore: unused_element
    Widget presenceRow() {
      final authUser = authProv.user;
      final effective = _buildEffectivePresenceUsers();
      if (effective.isEmpty) return const SizedBox.shrink();
      final authId = authUser?.id ?? -1;
      final me = effective.where((u) => u.userId == authId).firstOrNull;
      final others = effective.where((u) => u.userId != authId).toList();
      final visibleOthers = others.take(6).toList();
      final overflowCount = others.length - visibleOthers.length;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (me != null) _PresenceAvatar(presence: me, isMe: true),
          for (int i = 0; i < visibleOthers.length; i++) ...[
            const SizedBox(width: 8),
            _PresenceAvatar(
              presence: visibleOthers[i],
              isMe: false,
              zIndex: visibleOthers.length - i,
            ),
          ],
          if (overflowCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text('+$overflowCount',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700])),
            ),
          ],
          if (_pendingEditRequestCount > 0) ...[
            const SizedBox(width: 8),
            InkWell(
              onTap:
                  widget.onNavigateToEditRequests ?? _showPendingEditRequests,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.orange[700],
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_open, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('$_pendingEditRequestCount pending',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ],
      );
    }

    Widget activeUsersPanel() {
      final authUser = authProv.user;
      final users = _activeSheetUsers.isNotEmpty
          ? _activeSheetUsers
          : (authUser != null
              ? [
                  {
                    'user_id': authUser.id,
                    'username': authUser.username,
                    'full_name': authUser.fullName,
                    'is_you': true,
                  }
                ]
              : <Map<String, dynamic>>[]);

      if (users.isEmpty) return const SizedBox.shrink();

      String initialsOf(String text) {
        final parts = text
            .trim()
            .split(RegExp(r'\s+'))
            .where((p) => p.isNotEmpty)
            .toList();
        if (parts.isEmpty) return '?';
        if (parts.length == 1) {
          final t = parts.first;
          return t.length >= 2
              ? t.substring(0, 2).toUpperCase()
              : t.toUpperCase();
        }
        return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
      }

      Map<String, dynamic> enrichUser(Map<String, dynamic> user) {
        final uid = user['user_id'] is num
            ? (user['user_id'] as num).toInt()
            : int.tryParse('${user['user_id'] ?? ''}') ?? -1;
        final fromPresence = _presenceInfoMap[uid];
        final username = (user['username'] ?? '').toString();
        final fullName = ((user['full_name'] ?? '').toString().trim().isNotEmpty
                ? user['full_name']
                : username)
            .toString();
        final role = (fromPresence?.role ??
                user['role'] ??
                ((user['is_you'] == true) ? authUser?.role : '') ??
                '')
            .toString();
        final department =
            (fromPresence?.departmentName ?? user['department_name'])
                ?.toString();
        final isEditing = (fromPresence?.currentCell ?? '').trim().isNotEmpty;
        return {
          ...user,
          'user_id': uid,
          'username': username,
          'full_name': fullName,
          'role': role,
          'department': department,
          'is_editing': isEditing,
        };
      }

      final enriched = users.map(enrichUser).toList();
      final maxVisible = enriched.length > 3 ? 2 : enriched.length;
      final overflow = enriched.length > 3 ? enriched.length - 2 : 0;
      final visibleUsers = enriched.take(maxVisible).toList();

      final double avatarSize = 34;
      final double step = 24;
      final double overflowSlot = overflow > 0 ? avatarSize : 0;
      final double groupWidth = visibleUsers.isEmpty
          ? 0
          : ((visibleUsers.length - 1) * step) + avatarSize + overflowSlot;
      final double panelWidth = (108 + groupWidth).clamp(130, 260).toDouble();

      return SizedBox(
        height: 48,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: panelWidth,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '👥 ${enriched.length} Active',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF334155),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: groupWidth,
                height: 34,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (int i = 0; i < visibleUsers.length; i++)
                      Positioned(
                        left: i * step,
                        child: _ActiveUserBubble(
                          size: avatarSize,
                          userId: visibleUsers[i]['user_id'] as int,
                          fullName: visibleUsers[i]['full_name'] as String,
                          username: visibleUsers[i]['username'] as String,
                          role: (visibleUsers[i]['role'] ?? '').toString(),
                          department:
                              (visibleUsers[i]['department'] ?? '').toString(),
                          isYou: visibleUsers[i]['is_you'] == true,
                          isEditing: visibleUsers[i]['is_editing'] == true,
                          initials: initialsOf(
                              visibleUsers[i]['full_name'] as String),
                          avatarUrl:
                              (visibleUsers[i]['avatar_url'] ?? '').toString(),
                        ),
                      ),
                    if (overflow > 0)
                      Positioned(
                        left: visibleUsers.length * step,
                        child: Container(
                          width: avatarSize,
                          height: avatarSize,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFFE2E8F0),
                            border: Border.all(color: Colors.white, width: 1.8),
                          ),
                          child: Text(
                            '+$overflow',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF334155),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(
          bottom: BorderSide(color: _borderColor, width: 1),
        ),
      ),
      child: Row(
        children: [
          // ─ Back arrow (separate button) ─
          Tooltip(
            message: 'Back to Work Sheets',
            child: InkWell(
              onTap: () {
                setState(() {
                  _currentSheet = null;
                  _selectedRow = null;
                  _selectedCol = null;
                  _selectionEndRow = null;
                  _selectionEndCol = null;
                  _editingRow = null;
                  _editingCol = null;
                  _activeSheetUsers = [];
                });
              },
              borderRadius: BorderRadius.circular(6),
              child: const Padding(
                padding: EdgeInsets.all(5),
                child: Icon(Icons.arrow_back_ios_new, size: 18, color: _kGray),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // ─ Document icon (decorative) ─
          Icon(Icons.description, size: 22, color: Colors.green[700]),
          const SizedBox(width: 6),
          // ─ Sheet name + editor hint ─
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 200),
                child: Text(
                  _currentSheet?.name ?? 'Untitled',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (isLockedByMe)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.edit, size: 10, color: Colors.green[700]),
                  const SizedBox(width: 3),
                  Text('You are editing',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[700],
                          fontWeight: FontWeight.w500)),
                ])
              else if (isLockedByOther)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock, size: 10, color: Colors.orange),
                  const SizedBox(width: 3),
                  Text('$_lockedByUser is editing',
                      style: const TextStyle(
                          fontSize: 10,
                          color: Colors.orange,
                          fontWeight: FontWeight.w500)),
                ]),
            ],
          ),
          const SizedBox(width: 10),
          // ─ Save chip ─
          if (!widget.readOnly && !isViewer) saveChip(),
          const SizedBox(width: 8),
          // ─ Save button ─
          if (!widget.readOnly && !isViewer)
            ElevatedButton.icon(
              onPressed:
                  (_canEditSheet() && _hasUnsavedChanges) ? _saveSheet : null,
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Save', style: TextStyle(fontSize: 13)),
              style: ElevatedButton.styleFrom(
                backgroundColor: (_canEditSheet() && _hasUnsavedChanges)
                    ? _kGreen
                    : Colors.grey[300],
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                elevation: 0,
                minimumSize: const Size(0, 30),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          // ─ Center: QB Code / Product Name search bar ─
          Expanded(
            child: Center(
              child: SizedBox(
                width: 260,
                height: 32,
                child: TextField(
                  controller: _inventorySearchController,
                  decoration: InputDecoration(
                    hintText: 'Product Name or QB Code…',
                    hintStyle: TextStyle(fontSize: 12, color: _textSecondary),
                    prefixIcon: const Icon(Icons.search,
                        size: 16, color: AppColors.primaryBlue),
                    suffixIcon: _inventorySearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close,
                                size: 14, color: _textSecondary),
                            onPressed: () => setState(() {
                              _inventorySearchQuery = '';
                              _inventorySearchController.clear();
                            }),
                          )
                        : null,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    filled: true,
                    fillColor: _surfaceAltColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor, width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: _borderColor, width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.primaryBlue, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) =>
                      setState(() => _inventorySearchQuery = v.trim()),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // ─ Active users tracking panel (DB heartbeat) ─
          activeUsersPanel(),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Ribbon Toolbar (File / Edit / Structure tabs)
  // ═══════════════════════════════════════════════════════
  Widget _buildRibbonToolbar() {
    final isViewer =
        (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '') ==
            'viewer';
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(
          bottom: BorderSide(color: _borderColor, width: 1),
        ),
      ),
      child: Column(
        children: [
          // Tab headers
          Container(
            height: 32,
            color: _surfaceColor,
            child: Row(
              children: [
                _buildRibbonTab('All'),
                _buildRibbonTab('File'),
                _buildRibbonTab('Edit'),
                _buildRibbonTab('Structure'),
                _buildRibbonTab('Merge'),
                _buildRibbonTab('Format'),
                if (_isInventoryTrackerSheet()) _buildRibbonTab('Inventory'),
              ],
            ),
          ),
          // Tab content
          Container(
            height: _selectedRibbonTab == 'All' ? 72 : 52,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: _surfaceColor,
            child: _buildRibbonContent(isViewer),
          ),
        ],
      ),
    );
  }

  Widget _buildRibbonTab(String label) {
    final isSelected = _selectedRibbonTab == label;
    final selectedTextColor =
        _isDark ? const Color(0xFF93C5FD) : AppColors.primaryBlue;
    final unselectedTextColor =
        _isDark ? const Color(0xFFE2E8F0) : _textSecondary;
    return GestureDetector(
      onTap: () => setState(() => _selectedRibbonTab = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? (_isDark ? _kBlue.withOpacity(0.16) : const Color(0xFFF0F4FF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border(
            bottom: BorderSide(
              color: isSelected ? AppColors.primaryBlue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
            color: isSelected ? selectedTextColor : unselectedTextColor,
          ),
        ),
      ),
    );
  }

  Widget _buildRibbonContent(bool isViewer) {
    switch (_selectedRibbonTab) {
      case 'All':
        return _buildAllRibbon(isViewer);
      case 'File':
        return _buildFileRibbon(isViewer);
      case 'Edit':
        return _buildEditRibbon(isViewer);
      case 'Structure':
        return _buildStructureRibbon(isViewer);
      case 'Merge':
        return _buildMergeRibbon(isViewer);
      case 'Format':
        return _buildFormatRibbon(isViewer);
      case 'Inventory':
        return _buildInventoryRibbon(isViewer);
      default:
        return const SizedBox();
    }
  }

  // ── All ribbon: all groups in one scrollable bar ──
  Widget _buildAllRibbon(bool isViewer) {
    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    final isAdminOrEditor = role == 'admin' || role == 'editor';
    final canEdit = !isViewer && !widget.readOnly && _canEditSheet();

    // Builds a labeled bordered group container around a row of buttons.
    Widget group(String label, List<Widget> children) {
      return Container(
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < children.length; i++) ...[
                    children[i],
                    if (i < children.length - 1) const SizedBox(width: 4),
                  ],
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: _isDark ? const Color(0xFF0F172A) : Colors.grey[100],
                border: Border(
                  top: BorderSide(color: _borderColor),
                ),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(5),
                  bottomRight: Radius.circular(5),
                ),
              ),
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 10),
              child: Text(
                label,
                style: TextStyle(fontSize: 9, color: _textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    // Current cell formats for Format group
    final key = (_selectedRow != null && _selectedCol != null)
        ? '${_selectedRow!},${_selectedCol!}'
        : null;
    final formats =
        key != null ? (_cellFormats[key] ?? <String>{}) : <String>{};
    final isBold = formats.contains('bold');
    final isItalic = formats.contains('italic');
    final isUnderline = formats.contains('underline');

    final isLockedByMe = _isLocked &&
        _lockedByUser != null &&
        (_lockedByUser ==
                (Provider.of<AuthProvider>(context, listen: false)
                    .user
                    ?.username) ||
            role == 'admin');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── File ──
          group('File', [
            if (!isViewer && !widget.readOnly)
              _buildRibbonButton(
                  Icons.upload_file, 'Import', canEdit ? _importSheet : null),
            _buildRibbonButton(Icons.download, 'Export', _showExportMenu),
            if (!isViewer && !widget.readOnly)
              _buildRibbonButton(
                  Icons.add_circle_outline, 'New', _createNewSheet),
          ]),
          // ── Edit ──
          if (!isViewer &&
              !widget.readOnly &&
              (isAdminOrEditor || role == 'user'))
            group('Edit', [
              _buildRibbonButton(Icons.undo, 'Undo', _canUndo ? _undo : null),
              _buildRibbonButton(Icons.redo, 'Redo', _canRedo ? _redo : null),
              _buildRibbonButton(
                  Icons.edit, 'Edit', _isLocked ? null : _lockSheet),
              _buildRibbonButton(
                _isLocked ? Icons.lock : Icons.lock_outline,
                _isLocked ? 'Unlock' : 'Lock',
                _isLocked ? (isLockedByMe ? _unlockSheet : null) : _lockSheet,
              ),
              if ((role == 'admin' || role == 'editor') &&
                  _currentSheet != null)
                _buildRibbonButton(
                  _currentSheet!.shownToViewers
                      ? Icons.visibility
                      : Icons.visibility_off,
                  _currentSheet!.shownToViewers ? 'Hide' : 'Show',
                  () => _toggleSheetVisibility(
                    _currentSheet!.id,
                    !_currentSheet!.shownToViewers,
                  ),
                ),
            ]),
          // ── Structure ──
          if (!isViewer && !widget.readOnly)
            group('Structure', [
              _buildRibbonButton(Icons.view_column_outlined, '+Col',
                  canEdit ? _addColumn : null),
              _buildRibbonButton(Icons.view_column_outlined, '-Col',
                  canEdit ? _deleteColumn : null),
              _buildRibbonButton(
                  Icons.table_rows_outlined, '+Row', canEdit ? _addRow : null),
              _buildRibbonButton(Icons.table_rows_outlined, '-Row',
                  canEdit ? _deleteRow : null),
            ]),
          // ── Merge ──
          if (!isViewer && !widget.readOnly)
            group('Merge', [
              _buildRibbonButton(
                  Icons.call_merge, 'Merge', canEdit ? _mergeCells : null),
              _buildRibbonButton(
                  Icons.call_split, 'Unmerge', canEdit ? _unmergeCells : null),
            ]),
          // ── Format ──
          if (!isViewer && !widget.readOnly)
            group('Format', [
              _buildFormatToggle(Icons.format_bold, 'Bold', isBold,
                  () => _toggleFormat('bold')),
              _buildFormatToggle(Icons.format_italic, 'Italic', isItalic,
                  () => _toggleFormat('italic')),
              _buildFormatToggle(Icons.format_underlined, 'Underline',
                  isUnderline, () => _toggleFormat('underline')),
              _buildRibbonDivider(),
              _buildFormatToggle(Icons.format_align_left, 'Left', false,
                  () => _setAlignment(TextAlign.left)),
              _buildFormatToggle(Icons.format_align_center, 'Center', false,
                  () => _setAlignment(TextAlign.center)),
              _buildFormatToggle(Icons.format_align_right, 'Right', false,
                  () => _setAlignment(TextAlign.right)),
              _buildRibbonDivider(),
              _buildColorButton(Icons.format_color_text, 'Text Color',
                  _currentTextColor, true),
              _buildColorButton(Icons.format_color_fill, 'Fill',
                  _currentBackgroundColor, false),
              _buildRibbonDivider(),
              _buildRibbonButton(Icons.border_all, 'Borders',
                  canEdit ? _showBorderMenu : null),
            ]),
          // ── Inventory ──
          if (_isInventoryTrackerSheet())
            group('Inventory', [
              if (!isViewer && isAdminOrEditor)
                _buildRibbonButton(
                    Icons.calendar_month, 'Add Date', _addInventoryDateColumn),
              _buildRibbonButton(
                _inventoryFilterToday ? Icons.today : Icons.today_outlined,
                _inventoryFilterToday ? 'All Dates' : 'Today',
                _scrollToInventoryToday,
              ),
              _buildRibbonButton(
                _inventoryFilterWeek
                    ? Icons.calendar_view_month
                    : Icons.date_range,
                _inventoryFilterWeek ? 'All Dates' : 'This Week',
                () => setState(() {
                  _inventoryFilterWeek = !_inventoryFilterWeek;
                  _inventoryFilterToday = false;
                }),
              ),
              _buildRibbonButton(
                Icons.warning_amber_rounded,
                'Critical Alerts',
                _showCriticalAlertsModal,
              ),
            ]),
        ],
      ),
    );
  }

  // ── File ribbon: Import, Export, New ──
  Widget _buildFileRibbon(bool isViewer) {
    return Row(
      children: [
        if (!isViewer && !widget.readOnly) ...[
          _buildRibbonButton(Icons.upload_file, 'Import',
              _canEditSheet() ? _importSheet : null),
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

  // ── Inventory Tracker ribbon: Add Date Column, Today, This Week, Alert controls ──
  Widget _buildInventoryRibbon(bool isViewer) {
    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    final isAdminOrEditor = role == 'admin' || role == 'editor';
    final isAdmin = role == 'admin';
    return Row(
      children: [
        if (!isViewer && isAdminOrEditor) ...[
          _buildRibbonButton(
            Icons.calendar_month,
            'Add Date Column',
            _addInventoryDateColumn,
          ),
          const SizedBox(width: 6),
        ],
        _buildRibbonButton(
          _inventoryFilterToday ? Icons.today : Icons.today_outlined,
          _inventoryFilterToday ? 'All Dates' : 'Today',
          _scrollToInventoryToday,
        ),
        const SizedBox(width: 6),
        _buildRibbonButton(
          _inventoryFilterWeek ? Icons.calendar_view_month : Icons.date_range,
          _inventoryFilterWeek ? 'All Dates' : 'This Week',
          () => setState(() {
            _inventoryFilterWeek = !_inventoryFilterWeek;
            _inventoryFilterToday = false;
          }),
        ),
        if (isAdmin) ...[
          const SizedBox(width: 6),
          _buildRibbonButton(
            Icons.warning_amber_rounded,
            'Critical Alerts',
            _showCriticalAlertsModal,
          ),
        ],
      ],
    );
  }

  // ── Inventory: configurable critical alert threshold dialog ──
  // ignore: unused_element
  void _showCriticalThresholdDialog() {
    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    if (role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can change alert settings.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    double tempThreshold = _criticalThreshold.clamp(0.01, 1.0);
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _surfaceColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryBlue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune,
                    color: AppColors.primaryBlue, size: 20),
              ),
              const SizedBox(width: 10),
              const Text('Critical Alert Threshold',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Set when an item becomes critical based on used percentage.',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    '${(tempThreshold * 100).round()}% used',
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                ),
                Slider(
                  value: tempThreshold,
                  min: 0.01,
                  max: 1.0,
                  divisions: 99,
                  activeColor: AppColors.primaryOrange,
                  inactiveColor: _borderColor,
                  label: '${(tempThreshold * 100).round()}%',
                  onChanged: (v) => setLocal(() => tempThreshold = v),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('1%',
                        style: TextStyle(fontSize: 11, color: _textSecondary)),
                    Text('100%',
                        style: TextStyle(fontSize: 11, color: _textSecondary)),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFCDD2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: AppColors.primaryOrange),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Items at ${(tempThreshold * 100).round()}% used or higher will be marked critical.',
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.primaryOrange),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel', style: TextStyle(color: _textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() => _criticalThreshold = tempThreshold);
                Navigator.pop(ctx);
              },
              child: const Text('Apply', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Inventory: critical alerts modal ──
  double? _criticalDeficitPctForRow(Map<String, String> row) {
    final productName = (row['Product Name'] ?? '').trim();
    final code = (row['QB Code'] ?? row['QC Code'] ?? '').trim();
    if (productName.isEmpty && code.isEmpty) return null;

    double? numVal(String key) {
      final raw = (row[key] ?? '').replaceAll(',', '').trim();
      if (raw.isEmpty) return null;
      return double.tryParse(raw);
    }

    final critical = numVal('Critical');
    final totalQty = numVal('Total Quantity');

    // Critical rule: item is critical when Total Quantity is at or below Critical.
    if (critical == null || totalQty == null || critical <= 0) return null;
    if (totalQty > critical) return null;

    final pct = (critical - totalQty) / critical;
    return pct.clamp(0.0, 1.0);
  }

  List<Map<String, String>> _buildCriticalRows() {
    final criticalRows = <Map<String, String>>[];
    for (final row in _data) {
      final deficitPct = _criticalDeficitPctForRow(row);
      if (deficitPct == null) continue;

      final total = double.tryParse(row['Total Quantity'] ?? '') ?? 0;
      final stock = double.tryParse(row['Stock'] ?? '') ?? 0;
      final maintaining = double.tryParse(row['Maintaining'] ?? '') ?? 0;
      final critical = double.tryParse(row['Critical'] ?? '') ?? 0;
      final deficit = (critical - total).clamp(0, double.infinity);
      criticalRows.add({
        'Product Name': row['Product Name'] ?? '',
        'QB Code': row['QB Code'] ?? row['QC Code'] ?? '',
        'Maintaining': maintaining.toStringAsFixed(0),
        'Critical': critical.toStringAsFixed(0),
        'Stock': stock.toStringAsFixed(0),
        'Total Quantity': total.toStringAsFixed(0),
        'deficitQty': deficit.toStringAsFixed(0),
        'deficitPct': (deficitPct * 100).toStringAsFixed(1),
      });
    }
    return criticalRows;
  }

  void _showCriticalAlertsModal() {
    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    if (role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Only admins can open critical alerts.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final criticalRows = _buildCriticalRows();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ─ Header
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEBEE),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.warning_amber_rounded,
                          color: AppColors.primaryOrange, size: 24),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Critical Stock Alerts',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.primaryBlue),
                          ),
                          Text(
                            criticalRows.isEmpty
                                ? 'All products are within safe levels'
                                : '${criticalRows.length} product${criticalRows.length == 1 ? '' : 's'} at/below Critical quantity',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // ─ Content
                if (criticalRows.isEmpty) ...[
                  const SizedBox(height: 24),
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.check_circle_outline,
                              color: Colors.green[400], size: 48),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Critical Alerts',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700]),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'All products are stocked above\ntheir Critical quantity.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 13, color: Colors.grey[500]),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ] else ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'Rule: Total Quantity ≤ Critical',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFEBEE),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${criticalRows.length} critical item${criticalRows.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryOrange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: criticalRows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final r = criticalRows[i];
                        final deficitPctDouble =
                            double.tryParse(r['deficitPct'] ?? '0') ?? 0;
                        final severity = deficitPctDouble >= 50
                            ? const Color(0xFF7B0000)
                            : deficitPctDouble >= 25
                                ? AppColors.primaryOrange
                                : const Color(0xFFE57373);
                        return Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFEBEE),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFFCDD2)),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r['Product Name'] ?? '',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: AppColors.primaryBlue),
                                    ),
                                    if ((r['QB Code'] ?? '').isNotEmpty)
                                      Text(
                                        r['QB Code']!,
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500]),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  r['Stock'] ?? '',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  r['Total Quantity'] ?? '',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: severity,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: severity.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'CRIT ${r['Critical']}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: severity,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 10),
                // ─ Footer
                Row(
                  children: [
                    Icon(Icons.rule, size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 4),
                    Text(
                      'Rule: critical when Total Quantity ≤ Critical',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Edit ribbon: Edit, Lock, Hide ──
  Widget _buildEditRibbon(bool isViewer) {
    if (isViewer || widget.readOnly) {
      return Row(
        children: [
          Text('View-only mode',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';
    final canManage =
        userRole == 'admin' || userRole == 'editor' || userRole == 'user';
    final currentUsername = authProvider.user?.username ?? '';
    final isLockedByMe = _isLocked &&
        _lockedByUser != null &&
        (_lockedByUser == currentUsername || userRole == 'admin');

    return Row(
      children: [
        _buildRibbonButton(Icons.undo, 'Undo', _canUndo ? _undo : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.redo, 'Redo', _canRedo ? _redo : null),
        if (canManage) ...[
          const SizedBox(width: 6),
          _buildRibbonButton(Icons.edit, 'Edit', _isLocked ? null : _lockSheet),
          const SizedBox(width: 6),
          _buildRibbonButton(
            _isLocked ? Icons.lock : Icons.lock_outline,
            _isLocked ? 'Unlock' : 'Lock',
            _isLocked ? (isLockedByMe ? _unlockSheet : null) : _lockSheet,
          ),
        ],
        if ((userRole == 'admin' || userRole == 'editor') &&
            _currentSheet != null) ...[
          const SizedBox(width: 6),
          _buildRibbonButton(
            _currentSheet!.shownToViewers
                ? Icons.visibility
                : Icons.visibility_off,
            _currentSheet!.shownToViewers ? 'Hide' : 'Show',
            () => _toggleSheetVisibility(
              _currentSheet!.id,
              !_currentSheet!.shownToViewers,
            ),
          ),
        ],
      ],
    );
  }

  String _cellKey(int row, int col) => '$row,$col';

  void _toggleFormat(String format) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          final key = _cellKey(r, c);
          final current = Set<String>.from(_cellFormats[key] ?? <String>{});
          if (current.contains(format)) {
            current.remove(format);
          } else {
            current.add(format);
          }
          if (current.isEmpty) {
            _cellFormats.remove(key);
          } else {
            _cellFormats[key] = current;
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

  void _setTextColor(Color color) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      _currentTextColor = color;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellTextColors[_cellKey(r, c)] = color;
        }
      }
    });
  }

  void _setBackgroundColor(Color color) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      _currentBackgroundColor = color;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellBackgroundColors[_cellKey(r, c)] = color;
        }
      }
    });
  }

  // ── Merged Cells Helper Methods ──
  Map<String, int>? _getMergedCellBounds(int row, int col) {
    for (final range in _mergedCellRanges) {
      final parts = range.split(':');
      if (parts.length == 2) {
        final start = parts[0].split(',');
        final end = parts[1].split(',');
        final minRow = int.parse(start[0]);
        final minCol = int.parse(start[1]);
        final maxRow = int.parse(end[0]);
        final maxCol = int.parse(end[1]);

        if (row >= minRow && row <= maxRow && col >= minCol && col <= maxCol) {
          return {
            'minRow': minRow,
            'minCol': minCol,
            'maxRow': maxRow,
            'maxCol': maxCol,
          };
        }
      }
    }
    return null;
  }

  bool _isCellInMergedRange(int row, int col) {
    return _getMergedCellBounds(row, col) != null;
  }

  bool _isTopLeftOfMergedRange(int row, int col) {
    final bounds = _getMergedCellBounds(row, col);
    return bounds != null && bounds['minRow'] == row && bounds['minCol'] == col;
  }

  bool _shouldSkipCell(int row, int col) {
    // Skip rendering if cell is in a merged range but not the top-left cell
    return _isCellInMergedRange(row, col) && !_isTopLeftOfMergedRange(row, col);
  }

  void _setBorders(Map<String, bool> borders) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellBorders[_cellKey(r, c)] = Map.from(borders);
        }
      }
    });
  }

  void _setOutsideBorders() {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    final minRow = bounds['minRow']!;
    final maxRow = bounds['maxRow']!;
    final minCol = bounds['minCol']!;
    final maxCol = bounds['maxCol']!;

    setState(() {
      for (int r = minRow; r <= maxRow; r++) {
        for (int c = minCol; c <= maxCol; c++) {
          final isTopEdge = r == minRow;
          final isBottomEdge = r == maxRow;
          final isLeftEdge = c == minCol;
          final isRightEdge = c == maxCol;

          _cellBorders[_cellKey(r, c)] = {
            'top': isTopEdge,
            'bottom': isBottomEdge,
            'left': isLeftEdge,
            'right': isRightEdge,
          };
        }
      }
    });
  }

  void _mergeCells() {
    if (_selectedRow == null ||
        _selectedCol == null ||
        _selectionEndRow == null ||
        _selectionEndCol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select a range of cells to merge')),
      );
      return;
    }

    final bounds = _getSelectionBounds();
    final minRow = bounds['minRow']!;
    final maxRow = bounds['maxRow']!;
    final minCol = bounds['minCol']!;
    final maxCol = bounds['maxCol']!;

    if (minRow == maxRow && minCol == maxCol) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please select more than one cell to merge')),
      );
      return;
    }

    final rangeKey = '$minRow,$minCol:$maxRow,$maxCol';
    setState(() {
      _mergedCellRanges.add(rangeKey);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cells merged')),
    );
  }

  void _unmergeCells() {
    if (_selectedRow == null || _selectedCol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a merged cell to unmerge')),
      );
      return;
    }

    // Find if the selected cell is part of any merged range
    String? rangeToRemove;
    for (final range in _mergedCellRanges) {
      final parts = range.split(':');
      if (parts.length == 2) {
        final start = parts[0].split(',');
        final end = parts[1].split(',');
        final minRow = int.parse(start[0]);
        final minCol = int.parse(start[1]);
        final maxRow = int.parse(end[0]);
        final maxCol = int.parse(end[1]);

        if (_selectedRow! >= minRow &&
            _selectedRow! <= maxRow &&
            _selectedCol! >= minCol &&
            _selectedCol! <= maxCol) {
          rangeToRemove = range;
          break;
        }
      }
    }

    if (rangeToRemove != null) {
      setState(() {
        _mergedCellRanges.remove(rangeToRemove);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cells unmerged')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No merged cells found at selection')),
      );
    }
  }

  void _showBorderMenu() {
    if (_selectedRow == null || _selectedCol == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select cells first')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cell Borders'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.border_all),
              title: const Text('All Borders'),
              onTap: () {
                _setBorders(
                    {'top': true, 'right': true, 'bottom': true, 'left': true});
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('All borders applied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.border_outer),
              title: const Text('Outside Borders'),
              onTap: () {
                _setOutsideBorders();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Outside borders applied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.border_top),
              title: const Text('Top Border'),
              onTap: () {
                _setBorders({
                  'top': true,
                  'right': false,
                  'bottom': false,
                  'left': false
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Top border applied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.border_bottom),
              title: const Text('Bottom Border'),
              onTap: () {
                _setBorders({
                  'top': false,
                  'right': false,
                  'bottom': true,
                  'left': false
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Bottom border applied')),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.border_clear),
              title: const Text('No Borders'),
              onTap: () {
                _setBorders({
                  'top': false,
                  'right': false,
                  'bottom': false,
                  'left': false
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Borders removed')),
                );
              },
            ),
          ],
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

  // ignore: unused_element
  void _showFormulaDialog() {
    // TODO: Implement formula dialog
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Formula dialog coming soon')),
    );
  }

  // ignore: unused_element
  void _insertAutoSum() {
    if (_selectedRow == null || _selectedCol == null) return;
    // Insert a simple SUM formula
    _editController.text = '=SUM()';
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Auto sum added - specify range in formula bar')),
    );
  }

  Widget _buildFormatToggle(
      IconData icon, String tooltip, bool active, VoidCallback onPressed) {
    final iconColor = _isDark ? const Color(0xFFE2E8F0) : _kNavy;
    final activeBg = _isDark
        ? AppColors.primaryBlue.withOpacity(0.20)
        : _kNavy.withOpacity(0.12);
    final activeBorder = _isDark
        ? AppColors.primaryBlue.withOpacity(0.45)
        : _kNavy.withOpacity(0.3);
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
            color: active ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: active ? Border.all(color: activeBorder) : null,
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
      ),
    );
  }

  // ignore: unused_element
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
              style: TextStyle(
                  fontSize: 12, color: _kNavy, fontWeight: FontWeight.w500),
            ),
            Icon(Icons.arrow_drop_down, size: 16, color: Colors.grey[600]),
          ],
        ),
      ),
      itemBuilder: (_) => _fontSizeOptions.map((s) {
        return PopupMenuItem<double>(
          value: s,
          child: Text('${s.toInt()} px',
              style: TextStyle(
                fontSize: s.clamp(11, 18),
                fontWeight:
                    s == _currentFontSize ? FontWeight.bold : FontWeight.normal,
              )),
        );
      }).toList(),
    );
  }

  // ignore: unused_element
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
        const PopupMenuItem(
            value: TextAlign.left,
            child: Row(children: [
              Icon(Icons.format_align_left, size: 18),
              SizedBox(width: 8),
              Text('Left'),
            ])),
        const PopupMenuItem(
            value: TextAlign.center,
            child: Row(children: [
              Icon(Icons.format_align_center, size: 18),
              SizedBox(width: 8),
              Text('Center'),
            ])),
        const PopupMenuItem(
            value: TextAlign.right,
            child: Row(children: [
              Icon(Icons.format_align_right, size: 18),
              SizedBox(width: 8),
              Text('Right'),
            ])),
      ],
    );
  }

  // Color picker button widget
  Widget _buildColorButton(
      IconData icon, String tooltip, Color currentColor, bool isTextColor) {
    final colorOptions = [
      Colors.black,
      Colors.red,
      Colors.orange,
      Colors.yellow,
      Colors.green,
      Colors.blue,
      Colors.purple,
      Colors.grey,
      Colors.white,
    ];

    return PopupMenuButton<Color>(
      tooltip: tooltip,
      onSelected: (color) {
        if (isTextColor) {
          _setTextColor(color);
        } else {
          _setBackgroundColor(color);
        }
      },
      offset: const Offset(0, 36),
      child: Container(
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: _borderColor),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16, color: _isDark ? const Color(0xFFE2E8F0) : _kNavy),
            Container(
              height: 3,
              width: 20,
              color: currentColor,
            ),
          ],
        ),
      ),
      itemBuilder: (_) => colorOptions.map((color) {
        return PopupMenuItem<Color>(
          value: color,
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 8),
              Text(_getColorName(color)),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getColorName(Color color) {
    if (color == Colors.black) return 'Black';
    if (color == Colors.red) return 'Red';
    if (color == Colors.orange) return 'Orange';
    if (color == Colors.yellow) return 'Yellow';
    if (color == Colors.green) return 'Green';
    if (color == Colors.blue) return 'Blue';
    if (color == Colors.purple) return 'Purple';
    if (color == Colors.grey) return 'Grey';
    if (color == Colors.white) return 'White';
    return 'Custom';
  }

  // ── Structure ribbon: +Column, +Row, -Column, -Row ──
  Widget _buildStructureRibbon(bool isViewer) {
    if (isViewer || widget.readOnly) {
      return Row(
        children: [
          Text('View-only mode',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }
    return Row(
      children: [
        _buildRibbonButton(Icons.view_column_outlined, '+Column',
            _canEditSheet() ? _addColumn : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.view_column_outlined, '-Column',
            _canEditSheet() ? _deleteColumn : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.table_rows_outlined, '+Row',
            _canEditSheet() ? _addRow : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.table_rows_outlined, '-Row',
            _canEditSheet() ? _deleteRow : null),
      ],
    );
  }

  // ── Merge ribbon: Merge, Unmerge ──
  Widget _buildMergeRibbon(bool isViewer) {
    if (isViewer || widget.readOnly) {
      return Row(
        children: [
          Text('View-only mode',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }
    return Row(
      children: [
        _buildRibbonButton(
            Icons.call_merge, 'Merge', _canEditSheet() ? _mergeCells : null),
        const SizedBox(width: 6),
        _buildRibbonButton(Icons.call_split, 'Unmerge',
            _canEditSheet() ? _unmergeCells : null),
      ],
    );
  }

  // ── Format ribbon: Bold, Italic, Underline, Alignments, Colors, Borders ──
  Widget _buildFormatRibbon(bool isViewer) {
    if (isViewer || widget.readOnly) {
      return Row(
        children: [
          Text('View-only mode',
              style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        ],
      );
    }

    // Current selection formatting state
    final key = (_selectedRow != null && _selectedCol != null)
        ? '${_selectedRow!},${_selectedCol!}'
        : null;
    final formats =
        key != null ? (_cellFormats[key] ?? <String>{}) : <String>{};
    final isBold = formats.contains('bold');
    final isItalic = formats.contains('italic');
    final isUnderline = formats.contains('underline');

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          // Text formatting icons
          _buildFormatToggle(
              Icons.format_bold, 'Bold', isBold, () => _toggleFormat('bold')),
          _buildFormatToggle(Icons.format_italic, 'Italic', isItalic,
              () => _toggleFormat('italic')),
          _buildFormatToggle(Icons.format_underlined, 'Underline', isUnderline,
              () => _toggleFormat('underline')),
          _buildRibbonDivider(),

          // Alignment buttons
          _buildFormatToggle(Icons.format_align_left, 'Align Left', false,
              () => _setAlignment(TextAlign.left)),
          _buildFormatToggle(Icons.format_align_center, 'Align Center', false,
              () => _setAlignment(TextAlign.center)),
          _buildFormatToggle(Icons.format_align_right, 'Align Right', false,
              () => _setAlignment(TextAlign.right)),
          _buildRibbonDivider(),

          // Text Color
          _buildColorButton(
              Icons.format_color_text, 'Text Color', _currentTextColor, true),
          const SizedBox(width: 6),

          // Background Color
          _buildColorButton(Icons.format_color_fill, 'Background',
              _currentBackgroundColor, false),
          _buildRibbonDivider(),

          // Borders
          _buildRibbonButton(Icons.border_all, 'Borders',
              _canEditSheet() ? _showBorderMenu : null),
        ],
      ),
    );
  }

  // ── Formula ribbon tab label ──
  // ignore: unused_element
  Widget _buildFormulaRibbon(bool isViewer) {
    return Row(
      children: [
        const Icon(Icons.functions, size: 16, color: Color(0xFF2D6A4F)),
        const SizedBox(width: 6),
        Text(
          isViewer ? 'View-only mode' : 'Column formula builder shown below',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      ],
    );
  }

  // ── Column formula builder bar (shown below ribbon when Formula tab active) ──
  // ignore: unused_element
  Widget _buildColumnFormulaBar(bool isViewer) {
    final canEdit = !isViewer && !widget.readOnly && _canEditSheet();
    final cols = _columns;

    // ── Shared helpers ──
    Widget opBtn(_FormulaEntry entry, String op) {
      final selected = entry.op == op;
      return GestureDetector(
        onTap: canEdit
            ? () => setState(() {
                  entry.op = op;
                  if (op == '=' && entry.operandCols.length > 1) {
                    entry.operandCols = [entry.operandCols.first];
                  }
                })
            : null,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2D6A4F) : Colors.white,
            border: Border.all(
              color: selected ? const Color(0xFF2D6A4F) : Colors.grey[350]!,
            ),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            op,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      );
    }

    Widget colDropdown(String? value, ValueChanged<String?>? onChanged) {
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey[350]!),
          borderRadius: BorderRadius.circular(4),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: cols.contains(value) ? value : null,
            hint: Text(cols.isNotEmpty ? cols.first : '—',
                style: const TextStyle(fontSize: 12)),
            isDense: true,
            items: cols
                .map((c) => DropdownMenuItem(
                    value: c,
                    child: Text(c, style: const TextStyle(fontSize: 12))))
                .toList(),
            onChanged: canEdit ? onChanged : null,
          ),
        ),
      );
    }

    Widget labeled(String lbl, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(lbl,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey[500],
                    letterSpacing: 0.4)),
            const SizedBox(height: 2),
            child,
          ],
        );

    // ── Build one formula row ──
    Widget formulaRow(int idx) {
      final entry = _cfFormulas[idx];
      final isAssign = entry.op == '=';
      final operandCount = isAssign ? 1 : entry.operandCols.length;

      final opWidgets = <Widget>[];
      for (int i = 0; i < operandCount; i++) {
        opWidgets.add(
          labeled(
            'COL ${String.fromCharCode(65 + i)}',
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                colDropdown(
                  i < entry.operandCols.length ? entry.operandCols[i] : null,
                  (v) => setState(() {
                    while (entry.operandCols.length <= i) {
                      entry.operandCols.add(null);
                    }
                    entry.operandCols[i] = v;
                  }),
                ),
                if (!isAssign && i > 0 && canEdit) ...[
                  const SizedBox(width: 3),
                  GestureDetector(
                    onTap: () => setState(() => entry.operandCols.removeAt(i)),
                    child: Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red[200]!),
                        borderRadius: BorderRadius.circular(3),
                      ),
                      child:
                          Icon(Icons.close, size: 11, color: Colors.red[600]),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
        if (!isAssign && i < operandCount - 1) {
          opWidgets.add(Padding(
            padding: const EdgeInsets.only(top: 12, left: 6, right: 2),
            child: Text(entry.op,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ));
        }
        if (i < operandCount - 1) opWidgets.add(const SizedBox(width: 4));
      }

      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.amber[200]!),
          borderRadius: BorderRadius.circular(6),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Formula number badge
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  '${idx + 1}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 10),
              // Result column
              labeled(
                'RESULT',
                colDropdown(entry.resultCol,
                    (v) => setState(() => entry.resultCol = v)),
              ),
              const Padding(
                padding: EdgeInsets.only(top: 12, left: 6, right: 6),
                child: Text('=',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              // Operator
              labeled(
                'OPERATOR',
                Row(children: [
                  opBtn(entry, '+'),
                  const SizedBox(width: 3),
                  opBtn(entry, '-'),
                  const SizedBox(width: 3),
                  opBtn(entry, '*'),
                  const SizedBox(width: 3),
                  opBtn(entry, '/'),
                  const SizedBox(width: 3),
                  opBtn(entry, '='),
                ]),
              ),
              const SizedBox(width: 10),
              // Operand cols
              ...opWidgets,
              const SizedBox(width: 8),
              // + Add Column
              if (!isAssign && canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => entry.operandCols.add(null)),
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFF2D6A4F)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add, size: 13, color: Color(0xFF2D6A4F)),
                          SizedBox(width: 3),
                          Text('Add Col',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF2D6A4F))),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              // Apply this formula
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: ElevatedButton.icon(
                  onPressed: canEdit ? () => _applyColumnFormula(idx) : null,
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Apply',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2D6A4F),
                    foregroundColor: Colors.white,
                    minimumSize: const Size(70, 28),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              // Remove this formula row (only if more than 1)
              if (_cfFormulas.length > 1 && canEdit)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: GestureDetector(
                    onTap: () => setState(() => _cfFormulas.removeAt(idx)),
                    child: Container(
                      height: 28,
                      width: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        border: Border.all(color: Colors.red[200]!),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(Icons.delete_outline,
                          size: 15, color: Colors.red[600]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFDF6E3),
        border: Border(
          bottom: BorderSide(color: Colors.amber[300]!, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Icon(Icons.functions, size: 16, color: Color(0xFF2D6A4F)),
              const SizedBox(width: 6),
              const Text(
                'Column Formulas',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D6A4F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_cfFormulas.length}',
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              if (canEdit) ...[
                // Apply All
                if (_cfFormulas.length > 1)
                  TextButton.icon(
                    onPressed: _applyAllFormulas,
                    icon: const Icon(Icons.done_all,
                        size: 15, color: Color(0xFF2D6A4F)),
                    label: const Text('Apply All',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF2D6A4F))),
                    style: TextButton.styleFrom(
                        minimumSize: const Size(0, 28),
                        padding: const EdgeInsets.symmetric(horizontal: 8)),
                  ),
                const SizedBox(width: 6),
                // + Add Formula
                GestureDetector(
                  onTap: () => setState(() => _cfFormulas.add(_FormulaEntry())),
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFF2D6A4F)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 14, color: Color(0xFF2D6A4F)),
                        SizedBox(width: 4),
                        Text('Add Formula',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF2D6A4F))),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Clear All
                GestureDetector(
                  onTap: _clearColumnFormula,
                  child: Row(
                    children: [
                      Icon(Icons.close, size: 15, color: Colors.red[600]),
                      const SizedBox(width: 3),
                      Text('Clear All',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.red[600])),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          // Formula rows
          for (int i = 0; i < _cfFormulas.length; i++) formulaRow(i),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteFolder(Map<String, dynamic> folder) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';
    if (userRole != 'admin' && userRole != 'manager') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('You do not have permission to delete folders'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final name = folder['name'] ?? 'this folder';
    final sheetCount = int.tryParse('${folder['sheet_count'] ?? 0}') ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Folder'),
        content: Text(
          'Delete "$name"? ${sheetCount > 0 ? '$sheetCount sheet(s) inside will be moved to root. ' : ''}This cannot be undone.',
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
      try {
        await ApiService.deleteSheetFolder(folder['id'] as int);
        await _loadSheets();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Folder deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete folder: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // ── Apply a single formula entry to _data ──
  String? _applyFormulaEntry(_FormulaEntry entry) {
    final isAssign = entry.op == '=';
    final usedOperands =
        isAssign ? entry.operandCols.take(1).toList() : entry.operandCols;

    if (entry.resultCol == null) return 'Select a result column';
    if (usedOperands.isEmpty || usedOperands.any((c) => c == null)) {
      return 'Select all operand columns';
    }
    if (!isAssign && usedOperands.length < 2) {
      return 'Need at least 2 columns for this operator';
    }

    for (int i = 0; i < _data.length; i++) {
      if (isAssign) {
        _data[i][entry.resultCol!] = _data[i][usedOperands.first!] ?? '';
      } else {
        final values = usedOperands
            .map((col) => double.tryParse(_data[i][col!]?.toString() ?? ''))
            .toList();
        if (values.every((v) => v != null)) {
          double result = values.first!;
          for (int j = 1; j < values.length; j++) {
            final b = values[j]!;
            switch (entry.op) {
              case '+':
                result += b;
                break;
              case '-':
                result -= b;
                break;
              case '*':
                result *= b;
                break;
              case '/':
                result = b != 0 ? result / b : double.nan;
                break;
            }
          }
          if (!result.isNaN) {
            _data[i][entry.resultCol!] = result % 1 == 0
                ? result.toInt().toString()
                : result.toStringAsFixed(2);
          }
        }
      }
    }
    return null; // success
  }

  void _applyColumnFormula(int index) {
    if (index < 0 || index >= _cfFormulas.length) return;
    final entry = _cfFormulas[index];
    setState(() {});
    final err = _applyFormulaEntry(entry);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Formula ${index + 1}: $err')));
      return;
    }
    setState(() {});
    final isAssign = entry.op == '=';
    final expr = isAssign
        ? '${entry.operandCols.first}'
        : entry.operandCols.join(' ${entry.op} ');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Formula ${index + 1}: ${entry.resultCol} = $expr applied'),
      backgroundColor: const Color(0xFF2D6A4F),
    ));
    _markDirty();
    _saveSheet();
  }

  void _applyAllFormulas() {
    final errors = <String>[];
    setState(() {
      for (int i = 0; i < _cfFormulas.length; i++) {
        final err = _applyFormulaEntry(_cfFormulas[i]);
        if (err != null) errors.add('Formula ${i + 1}: $err');
      }
    });
    if (errors.isNotEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(errors.join('\n'))));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('${_cfFormulas.length} formula(s) applied'),
      backgroundColor: const Color(0xFF2D6A4F),
    ));
    _markDirty();
    _saveSheet();
  }

  void _clearColumnFormula() {
    setState(() => _cfFormulas = [_FormulaEntry()]);
  }

  // ── Ribbon sub-widgets ──
  Widget _buildRibbonButton(
      IconData icon, String label, VoidCallback? onPressed) {
    final enabled = onPressed != null;
    final fg = enabled
        ? (_isDark ? const Color(0xFFE2E8F0) : const Color(0xFF3C4043))
        : (_isDark ? const Color(0xFF94A3B8) : const Color(0xFFBDC1C6));
    final hover = _isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F3F4);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        hoverColor: hover,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            color: Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: fg,
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
      color: _borderColor,
      margin: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  // (collaborative controls are now inlined in _buildEditRibbon)

  // ignore: unused_element
  Widget _buildStatusBar() {
    if (_currentSheet == null) return const SizedBox();

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final currentUsername = authProvider.user?.username ?? '';
    final hasLock =
        _isLocked && _lockedByUser != null && _lockedByUser!.isNotEmpty;
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
  //  V2 Real-time Collaboration Methods
  // ═══════════════════════════════════════════════════════

  /// Wire up all V2 socket callbacks for presence, cell highlights, and edit requests.
  void _setupSheetPresenceCallbacks() {
    final socket = SocketService.instance;

    // Re-join the sheet room whenever the socket (re)connects so presence
    // updates are received even after a disconnect/reconnect cycle.
    socket.onConnect = () {
      if (!mounted) return;
      final sid = _currentSheet?.id;
      if (sid != null) {
        SocketService.instance.joinSheet(sid);
        // Immediately request presence, then again after all reconnecting
        // users have had time to re-join the room.
        SocketService.instance.getPresence(sid);
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && _currentSheet?.id == sid) {
            SocketService.instance.getPresence(sid);
          }
        });
      }
    };

    socket.onPresenceUpdate = (data) {
      if (!mounted) return;
      try {
        // Filter: ignore updates for a different sheet than the one open.
        // We normalise the id to int to tolerate num/double from JSON.
        final dynamic incomingRaw = data['sheet_id'];
        if (incomingRaw != null && _currentSheet != null) {
          final int incoming = incomingRaw is int
              ? incomingRaw
              : incomingRaw is num
                  ? incomingRaw.toInt()
                  : int.tryParse(incomingRaw.toString()) ?? -1;
          if (incoming != _currentSheet!.id) {
            return; // wrong sheet, skip silently
          }
        }

        final rawList = data['users'];
        if (rawList is! List) return;

        // Parse + deduplicate by userId. Skip malformed items so a single
        // bad entry doesn't blank the entire presence panel.
        final Map<int, CellPresence> seen = {};
        for (final raw in rawList.whereType<Map>()) {
          try {
            final payload = Map<String, dynamic>.from(raw);
            final dynamic rawId = payload['user_id'];
            final int? parsedId = rawId is num
                ? rawId.toInt()
                : int.tryParse((rawId ?? '').toString());
            if (parsedId == null || parsedId <= 0) continue;
            payload['user_id'] = parsedId;

            final user = CellPresence.fromJson(payload);
            if (!_isPresenceRoleSupported(user.role)) continue;

            final existing = seen[user.userId];
            seen[user.userId] =
                existing == null ? user : _pickRicherPresence(existing, user);
          } catch (userErr) {
            debugPrint(
                '[Presence] skipping invalid user payload: $userErr | raw=$raw');
          }
        }
        final users = seen.values.toList();

        setState(() {
          _presenceUsers = users;
          _presenceInfoMap
              .removeWhere((userId, _) => !seen.containsKey(userId));
          for (final u in users) {
            _presenceInfoMap[u.userId] = u;
          }
        });
        debugPrint(
            '[Presence] sheet=${_currentSheet?.id} users=${users.map((u) => u.username).join(', ')}');
      } catch (e) {
        debugPrint(
            '[Presence] Failed to parse presence_update: $e | data=$data');
      }
    };

    socket.onCellFocused = (data) {
      if (!mounted) return;
      final userId = data['user_id'] is num
          ? (data['user_id'] as num).toInt()
          : (data['user_id'] as int? ?? -1);
      final cellRef = data['cell_ref'] as String? ?? '';
      final cp = CellPresence(
        userId: userId,
        username: data['username'] as String? ?? 'User',
        fullName: data['full_name'] as String?,
        role: data['role'] as String? ?? '',
        departmentName: data['department_name'] as String?,
        currentCell: cellRef,
      );

      // Check BEFORE setState so we can act on it after.
      final alreadyPresent = _presenceUsers.any((u) => u.userId == userId);

      setState(() {
        _presenceInfoMap[userId] = cp;
        // ─── Ensure the user is in the presence panel ───────────────────────
        // If presence_update was missed (e.g. race on join), the cell_focused
        // event is our fallback signal that someone is actively in the sheet.
        if (!alreadyPresent) {
          _presenceUsers = [..._presenceUsers, cp];
        } else {
          // Refresh currentCell for the existing record
          _presenceUsers = [
            for (final u in _presenceUsers)
              u.userId == userId ? u.copyWith(currentCell: cellRef) : u
          ];
        }
        for (final v in _cellPresenceUserIds.values) {
          v.remove(userId);
        }
        _cellPresenceUserIds.putIfAbsent(cellRef, () => <int>{}).add(userId);
      });

      // If we just learned about a new user, immediately sync the full
      // presence list so all their details (full name, role) are correct.
      if (!alreadyPresent && _currentSheet != null) {
        SocketService.instance.getPresence(_currentSheet!.id);
      }
    };

    socket.onCellBlurred = (data) {
      if (!mounted) return;
      final userId = data['user_id'] is num
          ? (data['user_id'] as num).toInt()
          : (data['user_id'] as int? ?? -1);
      setState(() {
        for (final v in _cellPresenceUserIds.values) {
          v.remove(userId);
        }
      });
    };

    socket.onGrantTempAccess = (data) {
      if (!mounted) return;
      final cellRef = data['cell_ref'] as String? ?? '';
      // The proposed value has already been applied server-side and broadcast
      // via cell_updated. Show a confirmation so the editor knows it went through.
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Admin approved your edit request for cell $cellRef. '
            'The value has been applied.'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 6),
      ));
    };

    socket.onEditRequestNotification = (data) {
      if (!mounted) return;
      setState(() => _pendingEditRequestCount++);
    };

    socket.onEditRequestResolved = (data) {
      if (!mounted) return;
      setState(() {
        if (_pendingEditRequestCount > 0) _pendingEditRequestCount--;
      });
    };

    socket.onEditRequestSubmitted = (data) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Edit request submitted. Waiting for admin approval.'),
        backgroundColor: Colors.blue,
      ));
    };

    // ── Real-time cell sync: apply a remote user’s cell edit instantly ──
    socket.onCellUpdated = (data) {
      if (!mounted) return;
      try {
        final sheetId = data['sheet_id'] is num
            ? (data['sheet_id'] as num).toInt()
            : (int.tryParse(data['sheet_id']?.toString() ?? ''));
        final rowIndex = data['row_index'] is num
            ? (data['row_index'] as num).toInt()
            : (int.tryParse(data['row_index']?.toString() ?? ''));
        final colName = data['column_name'] as String? ?? '';
        final value = data['value']?.toString() ?? '';
        if (sheetId == null || rowIndex == null || colName.isEmpty) return;
        if (_currentSheet?.id != sheetId) return;
        if (rowIndex < 0) return;

        setState(() {
          // Expand _data if the incoming row is beyond current size (> 100 rows)
          while (_data.length <= rowIndex) {
            final emptyRow = <String, String>{};
            for (final c in _columns) {
              emptyRow[c] = '';
            }
            _data.add(emptyRow);
            _rowLabels.add('${_data.length}');
          }
          // If the column doesn't exist in this client's view yet, add it
          if (!_columns.contains(colName)) {
            _columns.add(colName);
            for (final r in _data) {
              r.putIfAbsent(colName, () => '');
            }
          }
          _data[rowIndex][colName] = value;
        });
        // Recalculate computed columns (e.g. Total Quantity) after remote edits
        if (_isInventoryTrackerSheet() &&
            _isInventoryTotalsInputColumn(colName)) {
          _recalcInventoryTotalsForRow(rowIndex);
        }
      } catch (e) {
        debugPrint('[onCellUpdated] error – falling back to full reload: $e');
        _reloadSheetDataOnly();
      }
    };

    // ── Full HTTP-save notification: another user explicitly saved the sheet ──
    // Re-sync this client's data from DB so the latest version is shown.
    socket.onSheetSaved = (data) {
      if (!mounted) return;
      final savedSheetId = data['sheet_id'] is num
          ? (data['sheet_id'] as num).toInt()
          : data['sheet_id'] as int?;
      final savedById = data['saved_by_id'] is num
          ? (data['saved_by_id'] as num).toInt()
          : data['saved_by_id'] as int?;
      if (savedSheetId == null || _currentSheet?.id != savedSheetId) return;

      // The user who saved already has the correct local data – skip reload.
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      if (savedById != null && savedById == authProvider.user?.id) return;

      // Don't disrupt a cell that is currently being edited.
      if (_editingRow != null) return;

      // Pull the latest persisted data from the server.
      _reloadSheetDataOnly();
    };
  }

  /// Re-fetch only the row/column data for the current sheet without
  /// resetting the socket room, presence list, or any other UI state.
  /// Used when another user's full save is broadcast via [sheet_saved].
  Future<void> _reloadSheetDataOnly() async {
    if (_currentSheet == null || !mounted) return;
    try {
      final response = await ApiService.getSheetData(_currentSheet!.id);
      if (!mounted) return;
      final sheet = SheetModel.fromJson(response['sheet']);
      if (!mounted) return;
      setState(() {
        if (sheet.columns.isNotEmpty) {
          _columns = List<String>.from(sheet.columns);
        }
        if (sheet.rows.isNotEmpty) {
          final newData = sheet.rows.map((r) {
            final row = <String, String>{};
            for (final col in _columns) {
              row[col] = r[col]?.toString() ?? '';
            }
            return row;
          }).toList();
          while (newData.length < 100) {
            final row = <String, String>{};
            for (final col in _columns) {
              row[col] = '';
            }
            newData.add(row);
          }
          _data = newData;
          _rowLabels = List.generate(_data.length, (i) => '${i + 1}');
        }
        // Recompute inventory totals if this is a tracker sheet
        if (_isInventoryTrackerSheet()) _recalcInventoryTotals();
        // Mark as saved – the server version is now the authoritative copy
        _saveStatus = 'saved';
        _hasUnsavedChanges = false;
      });
    } catch (e) {
      debugPrint('[SheetScreen] _reloadSheetDataOnly error: $e');
    }
  }

  /// Returns true when [row]/[col] is an inventory past-date column that is locked for editors.
  bool _isInventoryHistoricalCell(int row, int col) {
    if (!_isInventoryTrackerSheet()) return false;
    if (col < 0 || col >= _columns.length) return false;
    final colName = _columns[col];
    if (!colName.startsWith('DATE:')) return false;
    final parts = colName.split(':');
    if (parts.length < 3) return false;
    final cellDate = DateTime.tryParse(parts[1]); // 'YYYY-MM-DD'
    if (cellDate == null) return false;
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    return cellDate.isBefore(todayMidnight);
  }

  /// Presence avatar row shown above the spreadsheet grid.
  // ignore: unused_element
  Widget _buildPresencePanel() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final authUser = authProvider.user;
    final effective = _buildEffectivePresenceUsers();

    if (effective.isEmpty) return const SizedBox.shrink();

    final authId = authUser?.id ?? -1;
    final me = effective.where((u) => u.userId == authId).firstOrNull;
    final others = effective.where((u) => u.userId != authId).toList();
    // Number of others to show (cap at 8 + overflow badge)
    final visibleOthers = others.take(8).toList();
    final overflowCount = others.length - visibleOthers.length;

    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.group_outlined, size: 14, color: Colors.grey),
          const SizedBox(width: 6),
          Text(
            'In this sheet: ${effective.length} user${effective.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(width: 12),

          // ─── "You" avatar (always leftmost) ───
          if (me != null) ...[
            _PresenceAvatar(presence: me, isMe: true),
            const SizedBox(width: 6)
          ],

          // ─── Others – spaced row (no overlap) ───
          if (visibleOthers.isNotEmpty) ...[
            for (int i = 0; i < visibleOthers.length; i++) ...[
              const SizedBox(width: 6),
              _PresenceAvatar(
                presence: visibleOthers[i],
                isMe: false,
                zIndex: visibleOthers.length - i,
              ),
            ],
          ],

          // ─── Overflow count ───
          if (overflowCount > 0)
            Container(
              margin: const EdgeInsets.only(left: 6),
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              alignment: Alignment.center,
              child: Text('+$overflowCount',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[700])),
            ),

          const Spacer(),

          // ─── Admin: pending edit-requests badge ───
          if (_pendingEditRequestCount > 0)
            InkWell(
              onTap:
                  widget.onNavigateToEditRequests ?? _showPendingEditRequests,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.orange[700],
                    borderRadius: BorderRadius.circular(12)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_open, size: 12, color: Colors.white),
                    const SizedBox(width: 4),
                    Text('$_pendingEditRequestCount pending',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Shows a dialog for editors to request unlock of a locked historical cell.
  Future<void> _showEditRequestDialog(int row, int col) async {
    final cellRef = _getCellReference(row, col);
    final colName = _columns[col];
    final currentVal = _data[row][colName] ?? '';
    final proposedCtrl = TextEditingController(text: currentVal);

    final submitted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        surfaceTintColor: Colors.transparent,
        title: Row(children: [
          const Icon(Icons.lock_outline, color: Colors.orange),
          const SizedBox(width: 8),
          Text('Edit Request — $cellRef'),
        ]),
        content: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Column: $colName',
                    style: TextStyle(fontSize: 12, color: _textSecondary)),
                Text(
                    'Current value: ${currentVal.isEmpty ? "(empty)" : currentVal}',
                    style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 12),
                TextField(
                  controller: proposedCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Proposed new value',
                      border: OutlineInputBorder()),
                  autofocus: true,
                ),
                const SizedBox(height: 8),
                Text(
                  'This is a historical (past-date) record. An admin must approve '
                  'your request before you can edit it.',
                  style: TextStyle(fontSize: 11, color: _textSecondary),
                ),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _textSecondary))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send, size: 16),
            label: const Text('Submit Request'),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white),
          ),
        ],
      ),
    );

    if (submitted == true && mounted && _currentSheet != null) {
      final proposedValue = proposedCtrl.text;
      // Show immediate feedback so the user knows the request was sent.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Sending edit request…'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blueGrey,
      ));
      try {
        // HTTP is the reliable path — saves to DB and notifies admins via
        // socket even if the editor's own socket is momentarily reconnecting.
        await ApiService.submitEditRequest(
          sheetId: _currentSheet!.id,
          rowNumber: row + 1,
          columnName: colName,
          cellReference: cellRef,
          currentValue: currentVal,
          proposedValue: proposedValue,
        );
        // Also emit via socket for instant delivery if already connected.
        SocketService.instance.requestEdit(
          sheetId: _currentSheet!.id,
          rowNumber: row + 1,
          columnName: colName,
          cellRef: cellRef,
          currentValue: currentVal,
          proposedValue: proposedValue,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Edit request submitted. Waiting for admin approval.'),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 5),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Failed to submit request: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ));
        }
      }
    }
    proposedCtrl.dispose();
  }

  /// Admin: load and review pending edit requests for this sheet.
  Future<void> _showPendingEditRequests() async {
    if (_currentSheet == null) return;
    try {
      final requests = await ApiService.getEditRequests(_currentSheet!.id,
          status: 'pending');
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.lock_open, color: Colors.orange),
            const SizedBox(width: 8),
            const Text('Pending Edit Requests'),
          ]),
          content: SizedBox(
            width: 480,
            child: requests.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No pending requests.'))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: requests.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final req = requests[i];
                      return ListTile(
                        title: Text(
                            '${req['requester_username'] ?? 'Unknown'} — Cell ${req['cell_reference'] ?? req['column_name']}'),
                        subtitle: Text('Column: ${req['column_name']}\n'
                            'Proposed: ${req['proposed_value'] ?? '(not specified)'}\n'
                            'Requested: ${req['requested_at'] ?? ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.check_circle,
                                  color: Colors.green),
                              tooltip: 'Approve',
                              onPressed: () {
                                Navigator.pop(ctx);
                                // Use socket so backend immediately emits
                                // `edit_request_resolved` + `grant_temp_access`
                                // to the requesting editor in real-time.
                                SocketService.instance.resolveEditRequest(
                                  requestId: req['id'] as int,
                                  approved: true,
                                );
                                if (mounted) {
                                  setState(() {
                                    if (_pendingEditRequestCount > 0) {
                                      _pendingEditRequestCount--;
                                    }
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Request approved.'),
                                        backgroundColor: Colors.green),
                                  );
                                }
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              tooltip: 'Reject',
                              onPressed: () {
                                Navigator.pop(ctx);
                                SocketService.instance.resolveEditRequest(
                                  requestId: req['id'] as int,
                                  approved: false,
                                  rejectReason: 'Rejected by admin',
                                );
                                if (mounted) {
                                  setState(() {
                                    if (_pendingEditRequestCount > 0) {
                                      _pendingEditRequestCount--;
                                    }
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content: Text('Request rejected.'),
                                        backgroundColor: Colors.red),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to load requests: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Inventory Tracker – Dynamic Date Column Feature
  // ═══════════════════════════════════════════════════════

  static const double _invSubColW = 72.0; // width per IN/OUT sub-column
  static const double _invFixedColW = 120.0; // width for fixed columns
  static const double _invHeaderH1 = 32.0; // height of date-group header
  static const double _invHeaderH2 = 26.0; // height of IN/OUT sub-header

  String? _inventoryCodeColumn() {
    if (_columns.contains('QB Code')) return 'QB Code';
    if (_columns.contains('QC Code')) return 'QC Code';
    return null;
  }

  String _inventoryRowCode(Map<String, String> row) =>
      (row['QB Code'] ?? row['QC Code'] ?? '').toString();

  /// Returns true when the open sheet is an Inventory Tracker sheet.
  bool _isInventoryTrackerSheet() {
    return _columns.contains('Product Name') &&
        _inventoryCodeColumn() != null &&
        _columns.contains('Total Quantity');
  }

  List<String> _inventoryFrozenLeft() {
    final codeCol = _inventoryCodeColumn();
    return [
      'Product Name',
      if (codeCol != null) codeCol,
      'Stock',
      'Maintaining',
      'Critical',
    ].where(_columns.contains).toList();
  }

  List<String> _inventoryFrozenRight() =>
      ['Total Quantity'].where(_columns.contains).toList();

  /// Columns that are neither frozen nor date columns.
  static const _kLegacyInventoryCols = {'Reference No.', 'Remarks'};

  List<String> _inventoryMiscCols() => _columns
      .where((c) =>
          !_inventoryFrozenLeft().contains(c) &&
          !_inventoryFrozenRight().contains(c) &&
          !c.startsWith('DATE:') &&
          !_kLegacyInventoryCols.contains(c))
      .toList();

  /// Returns visible dates (all, only this week, or only today).
  List<String> _inventoryVisibleDates() {
    final keys = _columns.where((c) => c.startsWith('DATE:')).toList()..sort();
    final dates = <String>{};
    for (final k in keys) {
      final parts = k.split(':');
      if (parts.length == 3) dates.add(parts[1]);
    }
    final sorted = dates.toList()..sort();
    if (_inventoryFilterToday) {
      final todayStr = _inventoryDateStr(DateTime.now());
      return sorted.where((d) => d == todayStr).toList();
    }
    return _inventoryFilterWeek ? _inventoryCurrentWeekDates(sorted) : sorted;
  }

  List<String> _inventoryCurrentWeekDates(List<String> dates) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 6));
    return dates.where((d) {
      try {
        final dt = DateTime.parse(d);
        return !dt.isBefore(
                DateTime(weekStart.year, weekStart.month, weekStart.day)) &&
            !dt.isAfter(DateTime(weekEnd.year, weekEnd.month, weekEnd.day));
      } catch (_) {
        return true;
      }
    }).toList();
  }

  String _inventoryDateStr(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  String _inventoryDateLabel(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];
      return '${m[dt.month - 1]}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  // ── Actions ──────────────────────────────────────────

  /// Silently injects today's date column if it doesn't already exist.
  /// Called automatically on sheet open (admin / editor only).
  void _autoInjectTodayColumnIfNeeded() {
    if (!_isInventoryTrackerSheet()) return;
    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    if (role != 'admin' && role != 'editor') return;

    final todayStr = _inventoryDateStr(DateTime.now());
    final inKey = 'DATE:$todayStr:IN';
    final outKey = 'DATE:$todayStr:OUT';
    if (_columns.contains(inKey)) return; // already there

    setState(() {
      for (final old in ['Date', 'IN', 'OUT']) {
        _columns.remove(old);
        for (final row in _data) {
          row.remove(old);
        }
      }
      final totalIdx = _columns.indexOf('Total Quantity');
      if (totalIdx >= 0) {
        _columns.insert(totalIdx, inKey);
        _columns.insert(totalIdx + 1, outKey);
      } else {
        _columns.add(inKey);
        _columns.add(outKey);
      }
      for (final row in _data) {
        row.putIfAbsent(inKey, () => '');
        row.putIfAbsent(outKey, () => '');
      }
      _hasUnsavedChanges = true;
      _saveStatus = 'unsaved';
    });

    _recalcInventoryTotals();
    _saveSheet();
  }

  Future<void> _addInventoryDateColumn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null || !mounted) return;

    final dateStr = _inventoryDateStr(picked);
    final inKey = 'DATE:$dateStr:IN';
    final outKey = 'DATE:$dateStr:OUT';

    if (_columns.contains(inKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('A column for $dateStr already exists.')),
      );
      return;
    }

    setState(() {
      // First-time: remove static placeholder columns if still present.
      for (final old in ['Date', 'IN', 'OUT']) {
        _columns.remove(old);
        for (final row in _data) {
          row.remove(old);
        }
      }
      // Insert the new date pair just before Total Quantity.
      final totalIdx = _columns.indexOf('Total Quantity');
      if (totalIdx >= 0) {
        _columns.insert(totalIdx, inKey);
        _columns.insert(totalIdx + 1, outKey);
      } else {
        _columns.add(inKey);
        _columns.add(outKey);
      }
      for (final row in _data) {
        row.putIfAbsent(inKey, () => '');
        row.putIfAbsent(outKey, () => '');
      }
      _hasUnsavedChanges = true;
      _saveStatus = 'unsaved';
    });

    _recalcInventoryTotals();
    _saveSheet();
  }

  void _scrollToInventoryToday() {
    final todayStr = _inventoryDateStr(DateTime.now());
    final inKey = 'DATE:$todayStr:IN';

    if (!_columns.contains(inKey)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                "No column for today ($todayStr). Use \"Add Date Column\" first.")),
      );
      return;
    }

    // Toggle: if already showing only today, go back to all dates.
    if (_inventoryFilterToday) {
      setState(() {
        _inventoryFilterToday = false;
      });
      return;
    }

    // Filter to today only and turn off week filter.
    setState(() {
      _inventoryFilterToday = true;
      _inventoryFilterWeek = false;
    });

    // Scroll to today's column after layout settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      double offset = _rowNumWidth;
      for (final _ in _inventoryFrozenLeft()) {
        offset += _invFixedColW;
      }
      // Today is the only visible date, so offset lands right there.
      if (_horizontalScrollController.hasClients) {
        _horizontalScrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  void _recalcInventoryTotals() {
    setState(() {
      for (final row in _data) {
        final productName = (row['Product Name'] ?? '').trim();
        final code = _inventoryRowCode(row).trim();
        if (productName.isEmpty && code.isEmpty) {
          if (row.containsKey('Stock')) row['Stock'] = '';
          if (row.containsKey('Total Quantity')) row['Total Quantity'] = '';
          continue;
        }

        int totalIn = 0, totalOut = 0;
        for (final col in _columns) {
          if (col.startsWith('DATE:') && col.endsWith(':IN')) {
            totalIn += int.tryParse(row[col] ?? '0') ?? 0;
          } else if (col.startsWith('DATE:') && col.endsWith(':OUT')) {
            totalOut += int.tryParse(row[col] ?? '0') ?? 0;
          }
        }
        final currentStock = totalIn - totalOut;

        if (row.containsKey('Stock')) {
          row['Stock'] = currentStock.toString();
        }
        if (row.containsKey('Total Quantity')) {
          row['Total Quantity'] = currentStock.toString();
        }
      }
    });
  }

  bool _isInventoryTotalsInputColumn(String colName) {
    if (colName.startsWith('DATE:')) return true;
    return colName == 'Product Name' ||
        colName == 'QB Code' ||
        colName == 'QC Code' ||
        colName == 'Stock' ||
        colName == 'Total Quantity';
  }

  void _recalcInventoryTotalsForRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _data.length) return;
    final row = _data[rowIndex];
    final productName = (row['Product Name'] ?? '').trim();
    final code = _inventoryRowCode(row).trim();
    if (productName.isEmpty && code.isEmpty) {
      setState(() {
        if (row.containsKey('Stock')) row['Stock'] = '';
        if (row.containsKey('Total Quantity')) row['Total Quantity'] = '';
      });
      return;
    }

    int totalIn = 0, totalOut = 0;
    for (final col in _columns) {
      if (col.startsWith('DATE:') && col.endsWith(':IN')) {
        totalIn += int.tryParse(row[col] ?? '0') ?? 0;
      } else if (col.startsWith('DATE:') && col.endsWith(':OUT')) {
        totalOut += int.tryParse(row[col] ?? '0') ?? 0;
      }
    }
    final currentStock = totalIn - totalOut;

    setState(() {
      if (row.containsKey('Stock')) {
        row['Stock'] = currentStock.toString();
      }
      if (row.containsKey('Total Quantity')) {
        row['Total Quantity'] = currentStock.toString();
      }
    });
  }

  void _applyInvalidInventoryOutFallback({
    required int rowIndex,
    required String colName,
    required String previousValue,
    String? cellRef,
  }) {
    const fallbackValue = '0';
    final changed = previousValue != fallbackValue;
    if (changed) {
      _pushUndoSnapshot();
    }

    setState(() {
      _data[rowIndex][colName] = fallbackValue;
      _editingRow = null;
      _editingCol = null;
      if (cellRef != null) {
        _grantedCells.remove(cellRef);
      }
      _updateFormulaBar();
    });

    _recalcInventoryTotals();

    if (_currentSheet != null) {
      if (cellRef != null) {
        SocketService.instance.cellBlur(_currentSheet!.id, cellRef);
      }
      if (changed) {
        SocketService.instance.cellUpdate(
          _currentSheet!.id,
          rowIndex,
          colName,
          fallbackValue,
        );
      }
    }

    if (changed) {
      _markDirty();
      _saveSheet();
    }

    _showInvalidInventoryAmountDialog();
    _spreadsheetFocusNode.requestFocus();
  }

  bool _isInventoryRowIdentityEmpty(Map<String, String> row) {
    final productName = (row['Product Name'] ?? '').trim();
    final code = _inventoryRowCode(row).trim();
    return productName.isEmpty && code.isEmpty;
  }

  int _parseInventoryQtyOrZero(String? raw) {
    final trimmed = (raw ?? '').trim();
    return int.tryParse(trimmed.isEmpty ? '0' : trimmed) ?? 0;
  }

  Map<String, int> _inventoryTotalsForRow(
    Map<String, String> row, {
    String? overrideOutCol,
    int? overrideOutValue,
  }) {
    int totalIn = 0;
    int totalOut = 0;

    for (final c in _columns) {
      if (c.startsWith('DATE:') && c.endsWith(':IN')) {
        totalIn += _parseInventoryQtyOrZero(row[c]);
      } else if (c.startsWith('DATE:') && c.endsWith(':OUT')) {
        final value = (overrideOutCol != null && c == overrideOutCol)
            ? overrideOutValue ?? 0
            : _parseInventoryQtyOrZero(row[c]);
        totalOut += value;
      }
    }

    return {
      'totalIn': totalIn,
      'totalOut': totalOut,
      'net': totalIn - totalOut,
    };
  }

  bool _handleInvalidInventoryOutSubmission({
    required int rowIndex,
    required String colName,
    required String proposedValueRaw,
    required String previousValue,
    String? cellRef,
  }) {
    if (!_isInventoryOutEditInvalid(
      rowIndex: rowIndex,
      colName: colName,
      proposedValueRaw: proposedValueRaw,
    )) {
      return false;
    }

    _applyInvalidInventoryOutFallback(
      rowIndex: rowIndex,
      colName: colName,
      previousValue: previousValue,
      cellRef: cellRef,
    );
    return true;
  }

  bool _isInventoryOutEditInvalid({
    required int rowIndex,
    required String colName,
    required String proposedValueRaw,
  }) {
    if (!_isInventoryTrackerSheet()) return false;
    if (!colName.startsWith('DATE:') || !colName.endsWith(':OUT')) return false;
    if (rowIndex < 0 || rowIndex >= _data.length) return false;

    final row = _data[rowIndex];
    if (_isInventoryRowIdentityEmpty(row)) return false;

    final proposedTrimmed = proposedValueRaw.trim();
    final proposedOut =
        int.tryParse(proposedTrimmed.isEmpty ? '0' : proposedTrimmed);
    if (proposedOut == null || proposedOut < 0) return true;

    final currentOut = _parseInventoryQtyOrZero(row[colName]);
    final netBefore = _inventoryTotalsForRow(row)['net'] ?? 0;
    final netAfter = _inventoryTotalsForRow(
          row,
          overrideOutCol: colName,
          overrideOutValue: proposedOut,
        )['net'] ??
        0;

    if (netAfter >= 0) return false;

    final isReducingOut = proposedOut <= currentOut;
    if (netBefore < 0 && isReducingOut && netAfter >= netBefore) {
      return false;
    }

    return true;
  }

  Future<void> _showInvalidInventoryAmountDialog() async {
    if (!mounted || _invalidInventoryDialogOpen) return;
    _invalidInventoryDialogOpen = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid Amount'),
          content: const Text(
            'Invalid amount. OUT is set to 0 because total quantity cannot be negative.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      _invalidInventoryDialogOpen = false;
    }
  }

  void _deleteInventoryDateColumn(String dateStr) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Date Column'),
        content: Text(
            'Remove all data for ${_inventoryDateLabel(dateStr)}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _columns.remove('DATE:$dateStr:IN');
                _columns.remove('DATE:$dateStr:OUT');
                for (final row in _data) {
                  row.remove('DATE:$dateStr:IN');
                  row.remove('DATE:$dateStr:OUT');
                }
                _hasUnsavedChanges = true;
                _saveStatus = 'unsaved';
              });
              _recalcInventoryTotals();
              _saveSheet();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ── Grid rendering ────────────────────────────────────

  // ── Inventory search bar ──
  // ignore: unused_element
  Widget _buildInventorySearchBar() {
    return Container(
      color: const Color(0xFFF5F5F5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: SizedBox(
                height: 36,
                child: TextField(
                  controller: _inventorySearchController,
                  decoration: InputDecoration(
                    hintText: 'Search Product Name or QC Code…',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppColors.primaryBlue),
                    suffixIcon: _inventorySearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                size: 16, color: Color(0xFF888888)),
                            onPressed: () => setState(() {
                              _inventorySearchQuery = '';
                              _inventorySearchController.clear();
                            }),
                          )
                        : null,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFCCCCCC), width: 1),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: Color(0xFFCCCCCC), width: 1),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.primaryBlue, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (v) =>
                      setState(() => _inventorySearchQuery = v.trim()),
                ),
              ),
            ),
          ),
          if (_inventorySearchQuery.isNotEmpty)
            ...([
              const SizedBox(width: 10),
              Builder(builder: (ctx) {
                final hits = _data.where((row) {
                  final q = _inventorySearchQuery.toLowerCase();
                  return (row['Product Name'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(q) ||
                      _inventoryRowCode(row)
                          .toString()
                          .toLowerCase()
                          .contains(q);
                }).length;
                return Text(
                  '$hits result${hits == 1 ? '' : 's'}',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.primaryBlue),
                );
              }),
            ]),
        ],
      ),
    );
  }

  Widget _buildInventoryTrackerGrid() {
    return _buildInventoryTrackerGridContent();
  }

  Widget _buildInventoryTrackerGridContent() {
    return Focus(
      focusNode: _spreadsheetFocusNode,
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event);
      },
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent &&
              HardwareKeyboard.instance.isControlPressed) {
            if (signal.scrollDelta.dy < 0) {
              _zoomIn();
            } else {
              _zoomOut();
            }
          }
        },
        child: GestureDetector(
          onTap: () {
            if (_editingRow != null) {
              _saveEdit();
              _saveSheet();
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
              notificationPredicate: (n) => n.depth == 1,
              child: SingleChildScrollView(
                controller: _verticalScrollController,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SingleChildScrollView(
                    controller: _horizontalScrollController,
                    scrollDirection: Axis.horizontal,
                    child: _buildInventoryGridContent(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInventoryGridContent() {
    final frozenLeft = _inventoryFrozenLeft();
    final frozenRight = _inventoryFrozenRight();
    final miscCols = _inventoryMiscCols();
    final visibleDates = _inventoryVisibleDates();

    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    final isAdminOrEditor = role == 'admin' || role == 'editor';
    final isViewer = role == 'viewer';
    final todayStr = _inventoryDateStr(DateTime.now());

    final q = _inventorySearchQuery.toLowerCase();
    final filteredEntries = q.isEmpty
        ? _data.asMap().entries.toList()
        : _data.asMap().entries.where((e) {
            final row = e.value;
            return (row['Product Name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(q) ||
                _inventoryRowCode(row).toString().toLowerCase().contains(q);
          }).toList();

    final visibleColumnKeys = <String>[
      ...frozenLeft,
      for (final date in visibleDates) ...['DATE:$date:IN', 'DATE:$date:OUT'],
      ...miscCols,
      ...frozenRight,
    ];

    Map<String, int>? inventoryCellFromPosition(Offset localPosition) {
      final x = localPosition.dx / _zoomLevel;
      final y = localPosition.dy / _zoomLevel;
      final dataStartY = _invHeaderH1 + _invHeaderH2;

      if (x < _rowNumWidth || y < dataStartY) return null;

      final rowVisual = ((y - dataStartY) / _cellHeight).floor();
      if (rowVisual < 0 || rowVisual >= filteredEntries.length) return null;
      final row = filteredEntries[rowVisual].key;

      double accX = _rowNumWidth;
      for (final colKey in visibleColumnKeys) {
        final width = colKey.startsWith('DATE:') ? _invSubColW : _invFixedColW;
        if (x >= accX && x < accX + width) {
          final col = _columns.indexOf(colKey);
          if (col < 0) return null;
          return {'row': row, 'col': col};
        }
        accX += width;
      }

      return null;
    }

    // Total grid width
    double totalWidth = _rowNumWidth;
    for (final _ in frozenLeft) {
      totalWidth += _invFixedColW;
    }
    for (final _ in visibleDates) {
      totalWidth += _invSubColW * 2;
    }
    for (final _ in miscCols) {
      totalWidth += _invFixedColW;
    }
    for (final _ in frozenRight) {
      totalWidth += _invFixedColW;
    }

    // Approximate total height: two header rows + data rows.
    final double totalHeight =
        _invHeaderH1 + _invHeaderH2 + filteredEntries.length * _cellHeight + 16;

    final gridContent = SizedBox(
      width: totalWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 2-row grouped header
          _buildInventoryHeaderRows(
              frozenLeft, frozenRight, miscCols, visibleDates,
              canDelete: isAdminOrEditor && !widget.readOnly),
          // Data rows – filtered by search query
          ...filteredEntries.map((e) => _buildInventoryDataRow(
                e.key,
                frozenLeft,
                frozenRight,
                miscCols,
                visibleDates,
                isAdminOrEditor: isAdminOrEditor && !widget.readOnly,
                isViewer: isViewer,
                todayStr: todayStr,
              )),
        ],
      ),
    );

    // Wrap in a zoom-aware sized box so scroll extents scale with zoom.
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if ((event.buttons & kPrimaryMouseButton) == 0) return;
        final cell = inventoryCellFromPosition(event.localPosition);
        if (cell == null) return;

        if (_editingRow != null) {
          _saveEdit();
        }

        _isDragging = true;
        final isShift = HardwareKeyboard.instance.isShiftPressed;
        if (isShift && _selectedRow != null && _selectedCol != null) {
          _extendSelectionTo(cell['row']!, cell['col']!);
        } else {
          _selectCell(cell['row']!, cell['col']!);
        }
        _spreadsheetFocusNode.requestFocus();
      },
      onPointerMove: (event) {
        if (!_isDragging) return;
        final cell = inventoryCellFromPosition(event.localPosition);
        if (cell == null) return;
        _extendSelectionTo(cell['row']!, cell['col']!);
      },
      onPointerUp: (_) => _isDragging = false,
      onPointerCancel: (_) => _isDragging = false,
      child: SizedBox(
        width: totalWidth * _zoomLevel,
        height: totalHeight * _zoomLevel,
        child: Transform.scale(
          scale: _zoomLevel,
          alignment: Alignment.topLeft,
          child: gridContent,
        ),
      ),
    );
  }

  Widget _buildInventoryHeaderRows(
    List<String> frozenLeft,
    List<String> frozenRight,
    List<String> miscCols,
    List<String> visibleDates, {
    bool canDelete = false,
  }) {
    const Color darkNavy = Color(0xFF152D57);
    const Color navy = AppColors.primaryBlue;
    const Color midBlue = Color(0xFF2A4F8F);
    const Color subBlue = Color(0xFF3661A6);
    const Color todayCol = AppColors.primaryOrange;
    const Color todaySub = Color(0xFFE74C3C);
    const Color borderCol = Color(0xFF4A6FA5);
    const Color textCol = Colors.white;

    final todayStr = _inventoryDateStr(DateTime.now());

    BoxDecoration deco(Color bg) => BoxDecoration(
          color: bg,
          border: const Border(
            right: BorderSide(color: borderCol, width: 1),
            bottom: BorderSide(color: borderCol, width: 1),
          ),
        );

    final double fullHeaderH = _invHeaderH1 + _invHeaderH2;

    Widget hCell(String label, double w, double h, Color bg,
            {bool bold = true}) =>
        Container(
          width: w,
          height: h,
          alignment: Alignment.center,
          decoration: deco(bg),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: bold ? FontWeight.bold : FontWeight.w500,
              color: textCol,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        );

    // Date group header with embedded IN/OUT sub-header (no gap).
    Widget dateGroupCell(String date) {
      final isToday = date == todayStr;
      final bg = isToday ? todayCol : midBlue;
      final subBg = isToday ? todaySub : subBlue;
      final label = isToday
          ? '${_inventoryDateLabel(date)}  TODAY'
          : _inventoryDateLabel(date);
      return SizedBox(
        width: _invSubColW * 2,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _invSubColW * 2,
              height: _invHeaderH1,
              decoration: deco(bg),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: EdgeInsets.only(right: canDelete ? 18.0 : 0),
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: textCol,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                  if (canDelete)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: GestureDetector(
                        onTap: () => _deleteInventoryDateColumn(date),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.red[700],
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Icon(
                            Icons.close,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              children: [
                hCell('IN', _invSubColW, _invHeaderH2, subBg, bold: false),
                hCell('OUT', _invSubColW, _invHeaderH2, subBg, bold: false),
              ],
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: _rowNumWidth,
          height: fullHeaderH,
          decoration: deco(darkNavy),
          child: const Center(
            child: Icon(Icons.inventory_2_outlined,
                size: 14, color: Colors.white70),
          ),
        ),
        for (final col in frozenLeft)
          hCell(col, _invFixedColW, fullHeaderH, navy),
        for (final date in visibleDates) dateGroupCell(date),
        for (final col in miscCols)
          hCell(col, _invFixedColW, fullHeaderH, navy),
        for (final col in frozenRight)
          hCell(col, _invFixedColW, fullHeaderH, darkNavy),
      ],
    );
  }

  Widget _buildInventoryDataRow(
    int rowIndex,
    List<String> frozenLeft,
    List<String> frozenRight,
    List<String> miscCols,
    List<String> visibleDates, {
    required bool isAdminOrEditor,
    required bool isViewer,
    required String todayStr,
  }) {
    final row = _data[rowIndex];
    final bool isRowSelected = _selectedRow == rowIndex;
    final Color rowBg =
        rowIndex.isEven ? Colors.white : const Color(0xFFF8F9FA);

    // ── Total Quantity colour logic ──────────────────────────────────────────
    // Critical when Total Quantity <= Critical.
    Color? totalQtyColor() {
      final deficitPct = _criticalDeficitPctForRow(row);
      if (deficitPct == null) return AppColors.primaryBlue;
      return AppColors.primaryOrange;
    }

    Widget dataCell({
      required String colKey,
      required double width,
      required bool editable,
      bool autoCalc = false,
    }) {
      final colIdx = _columns.indexOf(colKey);
      final isEditing = _editingRow == rowIndex && _editingCol == colIdx;
      final isActiveCell = _selectedRow == rowIndex && _selectedCol == colIdx;
      final isInSel = colIdx >= 0 && _isInSelection(rowIndex, colIdx);
      final value = row[colKey] ?? '';

      // For the Total Quantity cell, derive background + text colours from
      // the Critical column rule.
      final bool isTotalQty = colKey == 'Total Quantity';
      final Color? totalQtyFgColor = isTotalQty ? totalQtyColor() : null;
      final Color? totalQtyBgColor = (isTotalQty &&
              totalQtyFgColor == AppColors.primaryOrange)
          ? const Color(0xFFFFF3E0) // light orange background for critical rows
          : null;

      Color bgColor() {
        if (isEditing) return Colors.white;
        if (isActiveCell) return const Color(0xFFBBD3FB);
        if (isInSel) return const Color(0xFFD2E3FC);
        if (isRowSelected) return const Color(0xFFE8F0FE);
        if (totalQtyBgColor != null) return totalQtyBgColor;
        return rowBg;
      }

      final bool isDateInOut = colKey.startsWith('DATE:');

      // Presence: is another user focused on this exact cell?
      final String cellRef =
          colIdx >= 0 ? _getCellReference(rowIndex, colIdx) : '';
      final Set<int> cellOccupantIds = cellRef.isNotEmpty
          ? (_cellPresenceUserIds[cellRef] ?? <int>{})
              .where((id) =>
                  id !=
                  (Provider.of<AuthProvider>(context, listen: false).user?.id ??
                      -1))
              .toSet()
          : <int>{};
      final CellPresence? cellOccupant = cellOccupantIds.isNotEmpty
          ? (_presenceInfoMap[cellOccupantIds.first] ??
              _presenceUsers
                  .where((u) => u.userId == cellOccupantIds.first)
                  .firstOrNull)
          : null;

      // Display rules:
      //  • No product/code set      → show empty for IN/OUT and Total Quantity
      //  • Product/code set, no data→ show '0' for date IN/OUT cells
      //  • Otherwise                → show the stored value
      final bool rowIdentityBlank =
          (row['Product Name'] ?? '').trim().isEmpty &&
              _inventoryRowCode(row).trim().isEmpty;
      final String displayValue;
      if (rowIdentityBlank && (isTotalQty || isDateInOut)) {
        displayValue = '';
      } else if (!rowIdentityBlank && isDateInOut && value.isEmpty) {
        displayValue = '0';
      } else {
        displayValue = value;
      }

      return GestureDetector(
        onTap: () {
          if (_editingRow != null) {
            _saveEdit();
          }
          if (colIdx >= 0) {
            final isShift = HardwareKeyboard.instance.isShiftPressed;
            if (isShift && _selectedRow != null && _selectedCol != null) {
              _extendSelectionTo(rowIndex, colIdx);
            } else {
              _selectCell(rowIndex, colIdx);
            }
          }
          _spreadsheetFocusNode.requestFocus();
        },
        onDoubleTap: (editable && !autoCalc && colIdx >= 0)
            ? () => _startEditing(rowIndex, colIdx)
            : null,
        child: Stack(
          children: [
            Container(
              width: width,
              height: _cellHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bgColor(),
                border: Border(
                  right: BorderSide(color: Colors.grey[300]!, width: 1),
                  bottom: BorderSide(color: Colors.grey[300]!, width: 1),
                ),
              ),
              child: isEditing
                  ? TextField(
                      controller: _editController,
                      focusNode: _focusNode,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: isDateInOut
                          ? const TextInputType.numberWithOptions(signed: false)
                          : TextInputType.text,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: isDateInOut ? (_) {} : null,
                      onSubmitted: (_) {
                        _saveEdit();
                      },
                    )
                  : Text(
                      displayValue,
                      style: TextStyle(
                        fontSize: 12,
                        color: totalQtyFgColor ??
                            (autoCalc ? AppColors.primaryBlue : Colors.black87),
                        fontWeight:
                            autoCalc ? FontWeight.w600 : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
            ),
            if (isActiveCell && !isEditing && colIdx >= 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.primaryBlue,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            if (isInSel && !isActiveCell && !isEditing && colIdx >= 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        top: _isSelectionEdge(rowIndex, colIdx, 'top')
                            ? const BorderSide(
                                color: AppColors.primaryBlue, width: 1.5)
                            : BorderSide.none,
                        bottom: _isSelectionEdge(rowIndex, colIdx, 'bottom')
                            ? const BorderSide(
                                color: AppColors.primaryBlue, width: 1.5)
                            : BorderSide.none,
                        left: _isSelectionEdge(rowIndex, colIdx, 'left')
                            ? const BorderSide(
                                color: AppColors.primaryBlue, width: 1.5)
                            : BorderSide.none,
                        right: _isSelectionEdge(rowIndex, colIdx, 'right')
                            ? const BorderSide(
                                color: AppColors.primaryBlue, width: 1.5)
                            : BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
            // ── Presence overlay: show colored border + initials avatar ──
            if (cellOccupant != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Tooltip(
                    message: '${cellOccupant.username} is here',
                    child: Container(
                      decoration: BoxDecoration(
                        color: cellOccupant.color.withOpacity(0.15),
                        border:
                            Border.all(color: cellOccupant.color, width: 1.5),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          margin: const EdgeInsets.only(top: 1, right: 2),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 3, vertical: 1),
                          decoration: BoxDecoration(
                            color: cellOccupant.color,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            cellOccupant.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    // Row number cell
    final cells = <Widget>[
      Container(
        width: _rowNumWidth,
        height: _cellHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              isRowSelected ? const Color(0xFF4472C4) : const Color(0xFFF5F5F5),
          border: Border(
            right: BorderSide(color: Colors.grey[400]!, width: 1),
            bottom: BorderSide(color: Colors.grey[300]!, width: 1),
          ),
        ),
        child: Text(
          '${rowIndex + 1}',
          style: TextStyle(
            fontSize: 11,
            color: isRowSelected ? Colors.white : Colors.grey[600],
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ];

    // Frozen left
    for (final col in frozenLeft) {
      cells.add(dataCell(
        colKey: col,
        width: _invFixedColW,
        editable: isAdminOrEditor,
      ));
    }

    // Date IN/OUT pairs
    for (final date in visibleDates) {
      // Any non-viewer can double-tap a date cell.
      // _startEditing will route them: historical → edit-request dialog,
      // today → direct edit (unless locked).  Admins bypass the dialog.
      final canEditDate = !isViewer;
      cells.add(dataCell(
        colKey: 'DATE:$date:IN',
        width: _invSubColW,
        editable: canEditDate,
      ));
      cells.add(dataCell(
        colKey: 'DATE:$date:OUT',
        width: _invSubColW,
        editable: canEditDate,
      ));
    }

    // Misc columns
    for (final col in miscCols) {
      cells.add(dataCell(
        colKey: col,
        width: _invFixedColW,
        editable: isAdminOrEditor,
      ));
    }

    // Frozen right (auto-calculated)
    for (final col in frozenRight) {
      cells.add(dataCell(
        colKey: col,
        width: _invFixedColW,
        editable: false,
        autoCalc: true,
      ));
    }

    return RepaintBoundary(child: Row(children: cells));
  }

  // ═══════════════════════════════════════════════════════
  //  Spreadsheet Grid – 4-panel layout with frozen headers & row nums
  // ═══════════════════════════════════════════════════════
  Widget _buildSpreadsheetGrid2() {
    // Width of data cells only (no row number column).
    double dataCellsWidth = 0;
    for (int c = 0; c < _columns.length; c++) {
      dataCellsWidth += _getColumnWidth(c);
    }
    // Total height of all data rows.
    double dataRowsHeight = 0;
    for (int r = 0; r < _data.length; r++) {
      dataRowsHeight += _getRowHeight(r);
    }
    dataRowsHeight += 40;

    return Focus(
      focusNode: _spreadsheetFocusNode,
      onKeyEvent: (node, event) {
        return _handleKeyEvent(event);
      },
      child: Listener(
        onPointerSignal: (signal) {
          if (signal is PointerScrollEvent &&
              HardwareKeyboard.instance.isControlPressed) {
            if (signal.scrollDelta.dy < 0) {
              _zoomIn();
            } else {
              _zoomOut();
            }
          }
        },
        child: GestureDetector(
          onTap: () {
            if (_editingRow != null) _saveEdit();
            _spreadsheetFocusNode.requestFocus();
          },
          child: Column(
            children: [
              // ── FROZEN COLUMN HEADER ROW ────────────────────────────────
              Row(
                children: [
                  _buildCornerCellWidget(),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _headerHScrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const NeverScrollableScrollPhysics(),
                      child: Transform.scale(
                        scale: _zoomLevel,
                        alignment: Alignment.topLeft,
                        child: SizedBox(
                          width: dataCellsWidth,
                          child: _buildHeaderRow(includeCorner: false),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              // ── SCROLLABLE DATA AREA ───────────────────────────────────
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── FROZEN ROW NUMBERS (V-scroll only, programmatic) ──
                    SingleChildScrollView(
                      controller: _rowNumVScrollController,
                      physics: const NeverScrollableScrollPhysics(),
                      child: SizedBox(
                        width: _rowNumWidth * _zoomLevel,
                        height: dataRowsHeight * _zoomLevel,
                        child: Transform.scale(
                          scale: _zoomLevel,
                          alignment: Alignment.topLeft,
                          child: SizedBox(
                            width: _rowNumWidth,
                            child: Column(
                              children: _data
                                  .asMap()
                                  .entries
                                  .map((e) => _buildRowNumCellWidget(e.key))
                                  .toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    // ── MAIN DATA CANVAS (H + V scrollable) ────────────────
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalScrollController,
                        thumbVisibility: true,
                        trackVisibility: true,
                        child: Scrollbar(
                          controller: _horizontalScrollController,
                          thumbVisibility: true,
                          trackVisibility: true,
                          notificationPredicate: (n) => n.depth == 1,
                          child: SingleChildScrollView(
                            controller: _verticalScrollController,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: SingleChildScrollView(
                                controller: _horizontalScrollController,
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: dataCellsWidth * _zoomLevel,
                                  height: dataRowsHeight * _zoomLevel,
                                  child: Transform.scale(
                                    scale: _zoomLevel,
                                    alignment: Alignment.topLeft,
                                    child: SizedBox(
                                      width: dataCellsWidth,
                                      child: Listener(
                                        behavior: HitTestBehavior.translucent,
                                        onPointerDown: (event) {
                                          if ((event.buttons &
                                                  kPrimaryMouseButton) ==
                                              0) {
                                            return;
                                          }
                                          final cell =
                                              _getCellFromDataAreaPosition(
                                                  event.localPosition);
                                          if (cell == null) return;

                                          if (_editingRow != null) {
                                            _saveEdit();
                                          }

                                          _isDragging = true;
                                          final isShift = HardwareKeyboard
                                              .instance.isShiftPressed;
                                          if (isShift &&
                                              _selectedRow != null &&
                                              _selectedCol != null) {
                                            _extendSelectionTo(
                                                cell['row']!, cell['col']!);
                                          } else {
                                            _selectCell(
                                                cell['row']!, cell['col']!);
                                          }
                                          _spreadsheetFocusNode.requestFocus();
                                        },
                                        onPointerMove: (event) {
                                          if (!_isDragging) return;
                                          final cell =
                                              _getCellFromDataAreaPosition(
                                                  event.localPosition);
                                          if (cell == null) return;
                                          _extendSelectionTo(
                                              cell['row']!, cell['col']!);
                                        },
                                        onPointerUp: (_) => _isDragging = false,
                                        onPointerCancel: (_) =>
                                            _isDragging = false,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: _data
                                              .asMap()
                                              .entries
                                              .map((e) => _buildDataRow(e.key,
                                                  includeRowNum: false))
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Get cell row/col from a position within the DATA CELLS area only
  /// (excludes column header and row number column).
  // ignore: unused_element
  Map<String, int>? _getCellFromDataAreaPosition(Offset localPosition) {
    final double x = localPosition.dx / _zoomLevel;
    final double y = localPosition.dy / _zoomLevel;
    if (x < 0 || y < 0) return null;

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

    int row = -1;
    double accY = 0;
    for (int r = 0; r < _data.length; r++) {
      final h = _getRowHeight(r);
      if (y >= accY && y < accY + h) {
        row = r;
        break;
      }
      accY += h;
    }
    if (row == -1 || row >= _data.length) return null;

    return {'row': row, 'col': col};
  }

  // ═══════════════════════════════════════════════════════
  //  Sheet Tabs at Bottom
  // ═══════════════════════════════════════════════════════
  Widget _buildSheetTabs() {
    final tabBarBg = _isDark ? const Color(0xFF0F172A) : Colors.grey[100]!;
    final tabDivider = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final tabInnerDivider =
        _isDark ? const Color(0xFF1F2937) : Colors.grey[200]!;
    final activeTabBg = _isDark ? const Color(0xFF111827) : Colors.white;
    final inactiveTabText =
        _isDark ? const Color(0xFF94A3B8) : Colors.grey[600]!;
    // Build tab list from loaded sheets, highlighting current
    final visibleSheets = _sheets.take(10).toList();
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: tabBarBg,
        border: Border(
          top: BorderSide(color: tabDivider, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Add sheet button
          if (!widget.readOnly &&
              (Provider.of<AuthProvider>(context, listen: false).user?.role ??
                      '') !=
                  'viewer')
            InkWell(
              onTap: _createNewSheet,
              child: Container(
                width: 30,
                height: 34,
                alignment: Alignment.center,
                child: Icon(Icons.add, size: 16, color: inactiveTabText),
              ),
            ),
          Container(width: 1, height: 34, color: tabDivider),
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
                      color: isActive ? activeTabBg : Colors.transparent,
                      border: Border(
                        right: BorderSide(color: tabInnerDivider, width: 1),
                        top: isActive
                            ? const BorderSide(
                                color: AppColors.primaryBlue, width: 2)
                            : BorderSide.none,
                      ),
                    ),
                    child: Text(
                      sheet.name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400,
                        color:
                            isActive ? AppColors.primaryBlue : inactiveTabText,
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
    final formulaBg = _isDark ? const Color(0xFF111827) : Colors.white;
    final formulaSubBg = _isDark ? const Color(0xFF0F172A) : Colors.grey[50]!;
    final formulaBorder = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final formulaText = _isDark ? const Color(0xFFE5E7EB) : Colors.black87;
    final formulaMuted = _isDark ? const Color(0xFF94A3B8) : Colors.grey[600]!;
    final cellRef = (_selectedRow != null && _selectedCol != null)
        ? _getCellReference(_selectedRow!, _selectedCol!)
        : '';
    final isReadOnly = widget.readOnly ||
        (Provider.of<AuthProvider>(context, listen: false).user?.role ?? '') ==
            'viewer';

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: formulaBg,
        border: Border(
          bottom: BorderSide(color: formulaBorder, width: 1),
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
                right: BorderSide(color: formulaBorder, width: 1),
              ),
              color: formulaSubBg,
            ),
            child: Text(
              cellRef,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: formulaText,
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
                right: BorderSide(color: formulaBorder, width: 1),
              ),
            ),
            child: Text(
              'fx',
              style: TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.bold,
                color: formulaMuted,
              ),
            ),
          ),
          // Formula/content input
          Expanded(
            child: TextField(
              controller: _formulaBarController,
              focusNode: _formulaBarFocusNode,
              readOnly: isReadOnly,
              style: TextStyle(fontSize: 13, color: formulaText),
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: InputBorder.none,
                isDense: true,
                hintStyle: TextStyle(color: formulaMuted),
              ),
              onTap: () {
                if (_selectedRow != null &&
                    _selectedCol != null &&
                    !isReadOnly) {
                  _startEditing(_selectedRow!, _selectedCol!);
                  if (_formulaBarController.text.isEmpty) {
                    _formulaBarController.text = '=';
                    _formulaBarController.selection =
                        TextSelection.collapsed(offset: 1);
                  }
                  _editController.text = _formulaBarController.text;
                }
              },
              onSubmitted: (value) {
                if (_selectedRow != null &&
                    _selectedCol != null &&
                    !isReadOnly) {
                  final int row = _selectedRow!;
                  final int col = _selectedCol!;
                  final colKey = _columns[col];
                  final cellRef = _getCellReference(row, col);
                  final oldVal = _data[row][colKey] ?? '';
                  if (_handleInvalidInventoryOutSubmission(
                    rowIndex: row,
                    colName: colKey,
                    proposedValueRaw: value,
                    previousValue: oldVal,
                    cellRef: cellRef,
                  )) {
                    return;
                  }
                  if (value != oldVal) {
                    _pushUndoSnapshot();
                  }
                  setState(() {
                    _data[row][colKey] = value;
                    _editingRow = null;
                    _editingCol = null;
                  });
                  if (value != oldVal) {
                    _markDirty();
                    _saveSheet();
                    if (_currentSheet != null) {
                      SocketService.instance.cellUpdate(
                        _currentSheet!.id,
                        row,
                        colKey,
                        value,
                      );
                    }
                  }
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

  // ignore: unused_element
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

  Widget _buildCornerCellWidget() {
    final headerBg =
        _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F8F8);
    final gridBorder = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final mutedIcon =
        _isDark ? const Color(0xFF94A3B8) : const Color(0xFF9AA0A6);
    return GestureDetector(
      onTap: () => setState(() {
        _selectedRow = 0;
        _selectedCol = 0;
        _selectionEndRow = _data.length - 1;
        _selectionEndCol = _columns.length - 1;
      }),
      child: Container(
        width: _rowNumWidth,
        height: _headerHeight,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: gridBorder, width: 1),
            bottom: BorderSide(color: gridBorder, width: 1),
          ),
          color: headerBg,
        ),
        child: Center(
          child: Icon(Icons.select_all, size: 13, color: mutedIcon),
        ),
      ),
    );
  }

  Widget _buildHeaderRow({bool includeCorner = true}) {
    final headerBg =
        _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F8F8);
    final gridBorder = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final headerText = _isDark ? const Color(0xFFE2E8F0) : Colors.grey[700]!;
    return Container(
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(color: gridBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (includeCorner) _buildCornerCellWidget(),
          // Column headers with resize handles
          ..._columns.asMap().entries.map((entry) {
            final colIndex = entry.key;
            final colWidth = _getColumnWidth(colIndex);
            final bounds = _getSelectionBounds();
            final isColSelected = _selectedRow != null &&
                colIndex >= bounds['minCol']! &&
                colIndex <= bounds['maxCol']!;

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
                          right: BorderSide(color: gridBorder, width: 1),
                        ),
                        color: isColSelected ? AppColors.lightBlue : headerBg,
                      ),
                      child: Text(
                        entry.value,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: isColSelected
                              ? AppColors.primaryBlue
                              : headerText,
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
                            if (_isResizingColumn &&
                                _resizingColumnIndex == colIndex) {
                              final delta =
                                  details.globalPosition.dx - _resizingStartX;
                              final newWidth = (_resizingStartWidth + delta)
                                  .clamp(_minCellWidth, 500.0);
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

  /// Standalone row-number cell widget (used by the frozen left strip).
  Widget _buildRowNumCellWidget(int rowIndex) {
    final rowHeaderBg =
        _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F8F8);
    final gridBorder = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final rowNumText =
        _isDark ? const Color(0xFF94A3B8) : const Color(0xFF9AA0A6);
    final bounds = _getSelectionBounds();
    final isRowInSelection = _selectedRow != null &&
        rowIndex >= bounds['minRow']! &&
        rowIndex <= bounds['maxRow']!;
    final rowHeight = _getRowHeight(rowIndex);
    return GestureDetector(
      onTap: () {
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
        height: rowHeight,
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: gridBorder, width: 1),
            bottom: BorderSide(color: gridBorder, width: 1),
          ),
          color: isRowInSelection ? AppColors.lightBlue : rowHeaderBg,
        ),
        child: Center(
          child: Text(
            _rowLabels[rowIndex],
            style: TextStyle(
              fontSize: 11,
              fontWeight: isRowInSelection ? FontWeight.w600 : FontWeight.w400,
              color: isRowInSelection ? AppColors.primaryBlue : rowNumText,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(int rowIndex, {bool includeRowNum = true}) {
    final gridBorder = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final rowEvenBg = _isDark ? const Color(0xFF111827) : Colors.white;
    final rowOddBg =
        _isDark ? const Color(0xFF0F172A) : const Color(0xFFFAFAFA);
    final editingBg = _isDark ? const Color(0xFF1F2937) : Colors.white;
    final cellTextColor = _isDark ? const Color(0xFFE5E7EB) : Colors.black87;
    final lockIconColor = _isDark ? const Color(0xFF94A3B8) : Colors.grey[500]!;
    final bounds = _getSelectionBounds();
    // ignore: unused_local_variable
    final isRowInSelection = _selectedRow != null &&
        rowIndex >= bounds['minRow']! &&
        rowIndex <= bounds['maxRow']!;
    final rowHeight = _getRowHeight(rowIndex);
    final isCollapsed = _collapsedRows.contains(rowIndex);

    return RepaintBoundary(
      child: Row(
        children: [
          if (includeRowNum) _buildRowNumCellWidget(rowIndex),
          // Data cells
          ..._columns.asMap().entries.map((entry) {
            final colIndex = entry.key;
            final colName = entry.value;

            // Skip cells that are covered by merged ranges
            if (_shouldSkipCell(rowIndex, colIndex)) {
              return const SizedBox.shrink();
            }

            final colWidth = _getColumnWidth(colIndex);
            final isEditing = _editingRow == rowIndex &&
                _editingCol == colIndex &&
                !isCollapsed;
            final isActiveCell =
                _selectedRow == rowIndex && _selectedCol == colIndex;
            final isInSel = _isInSelection(rowIndex, colIndex);
            final value = _data[rowIndex][colName] ?? '';

            // Check if this is a merged cell
            final mergeBounds = _getMergedCellBounds(rowIndex, colIndex);
            final isMerged = mergeBounds != null;
            double cellWidth = colWidth;
            double cellHeight = rowHeight;

            // Calculate merged cell dimensions
            if (isMerged && _isTopLeftOfMergedRange(rowIndex, colIndex)) {
              // Calculate total width
              cellWidth = 0;
              for (int c = mergeBounds['minCol']!;
                  c <= mergeBounds['maxCol']!;
                  c++) {
                cellWidth += _getColumnWidth(c);
              }
              // Calculate total height
              cellHeight = 0;
              for (int r = mergeBounds['minRow']!;
                  r <= mergeBounds['maxRow']!;
                  r++) {
                cellHeight += _getRowHeight(r);
              }
            }

            // Get custom borders
            final ck = _cellKey(rowIndex, colIndex);
            final customBorders = _cellBorders[ck];

            return GestureDetector(
              onTap: () {
                if (_isResizingColumn) return;
                if (isCollapsed) {
                  // If row is collapsed, expand it on cell click
                  _toggleRowCollapse(rowIndex);
                  return;
                }
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
                if (_isResizingColumn || isCollapsed) return;
                _startEditing(rowIndex, colIndex);
              },
              child: Container(
                width: cellWidth,
                height: cellHeight,
                decoration: BoxDecoration(
                  border: customBorders != null
                      ? Border(
                          top: customBorders['top'] == true
                              ? const BorderSide(color: Colors.black, width: 2)
                              : BorderSide(color: gridBorder, width: 1),
                          right: customBorders['right'] == true
                              ? const BorderSide(color: Colors.black, width: 2)
                              : BorderSide(color: gridBorder, width: 1),
                          bottom: customBorders['bottom'] == true
                              ? const BorderSide(color: Colors.black, width: 2)
                              : BorderSide(color: gridBorder, width: 1),
                          left: customBorders['left'] == true
                              ? const BorderSide(color: Colors.black, width: 2)
                              : BorderSide(color: gridBorder, width: 1),
                        )
                      : Border(
                          right: BorderSide(
                            color: gridBorder,
                            width: 1,
                          ),
                          bottom: BorderSide(
                            color: gridBorder,
                            width: 1,
                          ),
                        ),
                  color: () {
                    final ck = _cellKey(rowIndex, colIndex);
                    final customBg = _cellBackgroundColors[ck];
                    if (customBg != null && customBg != Colors.transparent) {
                      return customBg;
                    }
                    return isEditing
                        ? editingBg
                        : isActiveCell
                            ? const Color(0xFFE8F0FE)
                            : isInSel
                                ? const Color(0xFFD2E3FC)
                                : (rowIndex % 2 == 0 ? rowEvenBg : rowOddBg);
                  }(),
                ),
                child: Stack(
                  children: [
                    // Cell content (hidden when collapsed)
                    if (!isCollapsed) ...[
                      if (isEditing)
                        TextField(
                          controller: _editController,
                          focusNode: _focusNode,
                          style: TextStyle(
                              fontSize: 13,
                              fontFamily: 'Segoe UI',
                              color: cellTextColor),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            border: InputBorder.none,
                            isDense: true,
                            filled: true,
                            fillColor: editingBg,
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
                            cellAlign = _isNumeric(value)
                                ? Alignment.centerRight
                                : Alignment.centerLeft;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 6),
                            child: Align(
                              alignment: cellAlign,
                              child: Text(
                                value.startsWith('=')
                                    ? _evaluateFormula(value)
                                    : value,
                                style: TextStyle(
                                  fontSize: fontSize,
                                  color: _cellTextColors[ck] ?? cellTextColor,
                                  fontFamily: 'Segoe UI',
                                  fontWeight: fmts.contains('bold')
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontStyle: fmts.contains('italic')
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                  decoration: fmts.contains('underline')
                                      ? TextDecoration.underline
                                      : TextDecoration.none,
                                ),
                                overflow: isMerged
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                                maxLines: isMerged ? null : 1,
                              ),
                            ),
                          );
                        }),
                    ],
                    // Active cell border (thick blue like Excel) - hidden when collapsed
                    if (isActiveCell && !isEditing && !isCollapsed)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: AppColors.primaryBlue,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // Selection border (thin blue for range) - hidden when collapsed
                    if (isInSel && !isActiveCell && !isCollapsed)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border(
                                top: _isSelectionEdge(rowIndex, colIndex, 'top')
                                    ? const BorderSide(
                                        color: AppColors.primaryBlue,
                                        width: 1.5)
                                    : BorderSide.none,
                                bottom: _isSelectionEdge(
                                        rowIndex, colIndex, 'bottom')
                                    ? const BorderSide(
                                        color: AppColors.primaryBlue,
                                        width: 1.5)
                                    : BorderSide.none,
                                left:
                                    _isSelectionEdge(rowIndex, colIndex, 'left')
                                        ? const BorderSide(
                                            color: AppColors.primaryBlue,
                                            width: 1.5)
                                        : BorderSide.none,
                                right: _isSelectionEdge(
                                        rowIndex, colIndex, 'right')
                                    ? const BorderSide(
                                        color: AppColors.primaryBlue,
                                        width: 1.5)
                                    : BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                    // ── Presence indicator: full highlight when another user is on this cell ──
                    Builder(builder: (_) {
                      final cellRef = _getCellReference(rowIndex, colIndex);
                      final userIds = _cellPresenceUserIds[cellRef];
                      if (userIds == null || userIds.isEmpty) {
                        return const SizedBox.shrink();
                      }
                      final firstId = userIds.first;
                      final presenceUser = _presenceInfoMap[firstId] ??
                          _presenceUsers
                              .where((u) => u.userId == firstId)
                              .firstOrNull;
                      final color = presenceUser?.color ?? Colors.green;
                      final initials = presenceUser?.initials ?? '?';
                      final name = presenceUser?.username ?? 'User';
                      return Positioned.fill(
                        child: IgnorePointer(
                          child: Tooltip(
                            message: '$name is editing',
                            child: Container(
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.15),
                                border: Border.all(color: color, width: 1.5),
                              ),
                              child: Align(
                                alignment: Alignment.topRight,
                                child: Container(
                                  margin:
                                      const EdgeInsets.only(top: 1, right: 2),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 3, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: color,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    initials,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                    // ── Lock icon overlay for historical inventory cells ──
                    if (_isInventoryHistoricalCell(rowIndex, colIndex) &&
                        !_grantedCells
                            .contains(_getCellReference(rowIndex, colIndex)))
                      Positioned(
                        top: 2,
                        right: 2,
                        child: IgnorePointer(
                          child: Tooltip(
                            message:
                                'Historical record — request admin unlock to edit',
                            child: Icon(Icons.lock,
                                size: 10, color: lockIconColor),
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

  /// Check if a cell is on the edge of the selection range
  bool _isSelectionEdge(int row, int col, String edge) {
    final bounds = _getSelectionBounds();
    switch (edge) {
      case 'top':
        return row == bounds['minRow']!;
      case 'bottom':
        return row == bounds['maxRow']!;
      case 'left':
        return col == bounds['minCol']!;
      case 'right':
        return col == bounds['maxCol']!;
      default:
        return false;
    }
  }

  /// Check if a value looks numeric (right-align like Excel)
  bool _isNumeric(String value) {
    if (value.isEmpty) return false;
    return double.tryParse(value.replaceAll(',', '')) != null;
  }

  /// Bottom info bar showing selection info (like Excel status bar)
  Widget _buildSelectionInfoBar() {
    final statusBg =
        _isDark ? const Color(0xFF0F172A) : const Color(0xFFF3F3F3);
    final statusBorder = _isDark ? const Color(0xFF334155) : Colors.grey[300]!;
    final statusText = _isDark ? const Color(0xFFCBD5E1) : Colors.grey[700]!;
    final statusMuted = _isDark ? const Color(0xFF94A3B8) : Colors.grey[500]!;
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
        info +=
            '  |  Sum: ${sum.toStringAsFixed(2)}  |  Average: ${avg.toStringAsFixed(2)}';
      }
    } else if (_selectedRow != null && _selectedCol != null) {
      info = 'Cell: ${_getCellReference(_selectedRow!, _selectedCol!)}';
    }

    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: statusBg,
        border: Border(
          top: BorderSide(color: statusBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              info,
              style: TextStyle(
                fontSize: 11,
                color: statusText,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_data.isNotEmpty)
            Text(
              '${_data.length} rows × ${_columns.length} cols',
              style: TextStyle(
                fontSize: 11,
                color: statusMuted,
              ),
            ),
          const SizedBox(width: 12),
          // ── Zoom controls ──
          const VerticalDivider(width: 12, thickness: 1),
          InkWell(
            onTap: _zoomOut,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.remove, size: 14),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: _zoomReset,
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '${(_zoomLevel * 100).round()}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusText,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: _zoomIn,
            borderRadius: BorderRadius.circular(4),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Icon(Icons.add, size: 14),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// TEMPLATE PICKER DIALOG
// =============================================================================

class _TemplatePickerDialog extends StatefulWidget {
  const _TemplatePickerDialog();

  @override
  State<_TemplatePickerDialog> createState() => _TemplatePickerDialogState();
}

class _TemplatePickerDialogState extends State<_TemplatePickerDialog> {
  int? _hoveredIndex;

  static const List<Map<String, dynamic>> _templates =
      _SheetScreenState._kTemplates;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: _SheetScreenState._kBorder, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ──
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _SheetScreenState._kBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _SheetScreenState._kBorder, width: 1),
                    ),
                    child: const Icon(
                      Icons.dashboard_customize_outlined,
                      color: _SheetScreenState._kGreen,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Choose a Template',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _SheetScreenState._kNavy,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Start your sheet with a pre-defined structure. You can customise it afterwards.',
                          style: const TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: _SheetScreenState._kGray,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    color: _SheetScreenState._kGray,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              const Divider(height: 1, color: _SheetScreenState._kBorder),
              const SizedBox(height: 16),

              // ── Template cards grid ──
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: _templates.length,
                  itemBuilder: (ctx, i) {
                    final t = _templates[i];
                    final color = Color(t['colorValue'] as int);
                    final icon = IconData(
                      t['iconData'] as int,
                      fontFamily: 'MaterialIcons',
                    );
                    final cols = List<String>.from(t['columns'] as List);
                    final isHovered = _hoveredIndex == i;

                    return MouseRegion(
                      onEnter: (_) => setState(() => _hoveredIndex = i),
                      onExit: (_) => setState(() => _hoveredIndex = null),
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context, t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          decoration: BoxDecoration(
                            color: isHovered
                                ? _SheetScreenState._kBg
                                : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isHovered
                                  ? color.withOpacity(0.55)
                                  : _SheetScreenState._kBorder,
                              width: 1.2,
                            ),
                            boxShadow: isHovered
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.05),
                                      blurRadius: 10,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : [],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Icon + name row
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: _SheetScreenState._kBg,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: _SheetScreenState._kBorder,
                                      ),
                                    ),
                                    child: Icon(icon, color: color, size: 20),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      t['name'] as String,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: _SheetScreenState._kNavy,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),

                              const SizedBox(height: 8),

                              // Description
                              Text(
                                t['description'] as String,
                                style: const TextStyle(
                                  fontSize: 11,
                                  height: 1.25,
                                  color: _SheetScreenState._kGray,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),

                              const SizedBox(height: 8),

                              // Column chips preview
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: cols.take(4).map((c) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: _SheetScreenState._kBg,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: _SheetScreenState._kBorder,
                                      ),
                                    ),
                                    child: Text(
                                      c,
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: color,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  );
                                }).toList()
                                  ..addAll(cols.length > 4
                                      ? [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _SheetScreenState._kBg,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color:
                                                    _SheetScreenState._kBorder,
                                              ),
                                            ),
                                            child: Text(
                                              '+${cols.length - 4} more',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                color: _SheetScreenState._kGray,
                                              ),
                                            ),
                                          )
                                        ]
                                      : []),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 16),
              const Divider(height: 1, color: _SheetScreenState._kBorder),
              const SizedBox(height: 12),

              // ── Footer ──
              Row(
                children: [
                  const Icon(Icons.info_outline,
                      size: 14, color: _SheetScreenState._kGray),
                  const SizedBox(width: 6),
                  Text(
                    'Templates pre-fill column headers and a sample row. All content is editable.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: _SheetScreenState._kGray,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                    style: TextButton.styleFrom(
                      foregroundColor: _SheetScreenState._kGray,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
//  _PresenceAvatar — bubble shown in the presence panel for each
//  collaborator who currently has this sheet open.
//
//  • Coloured circle with initials
//  • Green "active / online" dot at bottom-right
//  • "You" label badge on the current user's avatar
//  • Hover → rich tooltip: name, role, department, current cell
// ═══════════════════════════════════════════════════════════════
class _PresenceAvatar extends StatefulWidget {
  final CellPresence presence;
  final bool isMe;
  final int zIndex; // controls Stack z-ordering

  const _PresenceAvatar({
    required this.presence,
    required this.isMe,
    this.zIndex = 0,
  });

  @override
  State<_PresenceAvatar> createState() => _PresenceAvatarState();
}

class _PresenceAvatarState extends State<_PresenceAvatar> {
  bool _hovered = false;
  bool _pinned = false; // popover stays open after tap
  OverlayEntry? _overlay;
  final _key = GlobalKey();

  CellPresence get p => widget.presence;

  @override
  void dispose() {
    _removeOverlay();
    super.dispose();
  }

  void _removeOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay() {
    _removeOverlay();
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;
    final isEditing = p.currentCell != null;
    const popupWidth = 240.0;

    _overlay = OverlayEntry(
      builder: (overlayCtx) {
        final screenWidth = MediaQuery.of(overlayCtx).size.width;
        // If popup would overflow the right edge, right-align it to the avatar.
        double left;
        if (offset.dx - 8 + popupWidth > screenWidth - 8) {
          left = (offset.dx + size.width - popupWidth)
              .clamp(8.0, screenWidth - popupWidth - 8);
        } else {
          left = offset.dx - 8;
        }
        return Positioned(
          left: left,
          top: offset.dy + size.height + 6,
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(minWidth: 180, maxWidth: 240),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2533),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Avatar + name header ──
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: p.color,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withOpacity(0.3), width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(p.initials,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isMe ? '${p.fullName} (You)' : p.fullName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (p.fullName != p.username)
                              Text('@${p.username}',
                                  style: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 10)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Divider(color: Color(0xFF2E3A4E), height: 1),
                  const SizedBox(height: 8),
                  // ── Role ──
                  _TooltipRow(
                    icon: Icons.shield_outlined,
                    label: 'Role',
                    text: p.role.isEmpty ? 'Unknown' : _capitalize(p.role),
                  ),
                  // ── Department ──
                  if (p.departmentName != null)
                    _TooltipRow(
                      icon: Icons.business_outlined,
                      label: 'Dept',
                      text: p.departmentName!,
                    ),
                  const SizedBox(height: 4),
                  // ── Status ──
                  _TooltipRow(
                    icon: isEditing
                        ? Icons.edit_outlined
                        : Icons.visibility_outlined,
                    label: 'Status',
                    text:
                        isEditing ? 'Editing cell ${p.currentCell}' : 'Viewing',
                    highlight: isEditing,
                  ),
                  // ── Online indicator ──
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: Color(0xFF22C55E), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 5),
                      const Text('Online',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFF86EFAC))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlay!);
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      key: _key,
      onEnter: (_) {
        setState(() => _hovered = true);
        if (!_pinned) _showOverlay();
      },
      onExit: (_) {
        setState(() => _hovered = false);
        if (!_pinned) _removeOverlay();
      },
      child: GestureDetector(
        onTap: () {
          setState(() => _pinned = !_pinned);
          if (_pinned) {
            _showOverlay();
          } else {
            _removeOverlay();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white,
              width: 2.5,
            ),
            boxShadow: (_hovered || _pinned)
                ? [
                    BoxShadow(
                      color: p.color.withOpacity(0.55),
                      blurRadius: 8,
                      spreadRadius: 1,
                    )
                  ]
                : [],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // ── Main circle ──
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.color,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  p.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0,
                  ),
                ),
              ),
              // ── Green active dot (bottom-right) ──
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: const Color(0xFF22C55E),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
              // ── "You" label (top-right) for current user ──
              if (widget.isMe)
                Positioned(
                  top: -6,
                  right: -6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBlue,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text('You',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              // ── Pinned indicator ring ──
              if (_pinned)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ),
            ],
          ), // closes Stack
        ), // closes AnimatedContainer
      ), // closes GestureDetector
    ); // closes MouseRegion
  }
}

class _ActiveUserBubble extends StatefulWidget {
  final double size;
  final int userId;
  final String fullName;
  final String username;
  final String role;
  final String department;
  final bool isYou;
  final bool isEditing;
  final String initials;
  final String avatarUrl;

  const _ActiveUserBubble({
    required this.size,
    required this.userId,
    required this.fullName,
    required this.username,
    required this.role,
    required this.department,
    required this.isYou,
    required this.isEditing,
    required this.initials,
    required this.avatarUrl,
  });

  @override
  State<_ActiveUserBubble> createState() => _ActiveUserBubbleState();
}

class _ActiveUserBubbleState extends State<_ActiveUserBubble> {
  static _ActiveUserBubbleState? _activeOwner;
  OverlayEntry? _overlay;
  Timer? _hoverDelay;
  bool _hovered = false;
  Offset _cursorGlobal = Offset.zero;

  Color get _avatarColor =>
      kPresenceColors[widget.userId.abs() % kPresenceColors.length];

  String _cap(String text) {
    final v = text.trim();
    if (v.isEmpty) return 'Unknown';
    return '${v[0].toUpperCase()}${v.substring(1)}';
  }

  void _hideOverlay() {
    _hoverDelay?.cancel();
    _hoverDelay = null;
    _overlay?.remove();
    _overlay = null;
    if (_activeOwner == this) _activeOwner = null;
  }

  void _scheduleShow() {
    _hoverDelay?.cancel();
    _hoverDelay = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || !_hovered) return;
      _showOverlay();
    });
  }

  void _showOverlay() {
    if (!mounted) return;

    if (_activeOwner != null && _activeOwner != this) {
      _activeOwner!._hideOverlay();
    }
    _activeOwner = this;

    _overlay?.remove();

    _overlay = OverlayEntry(
      builder: (overlayCtx) {
        const cardWidth = 240.0;
        final screen = MediaQuery.of(overlayCtx).size;
        var left = _cursorGlobal.dx + 14;
        var top = _cursorGlobal.dy + 14;

        if (left + cardWidth > screen.width - 8) {
          left = (_cursorGlobal.dx - cardWidth - 14)
              .clamp(8.0, screen.width - cardWidth - 8);
        }
        if (top + 160 > screen.height - 8) {
          top = (_cursorGlobal.dy - 160).clamp(8.0, screen.height - 168);
        }

        return Positioned(
          left: left,
          top: top,
          child: IgnorePointer(
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: cardWidth,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E2533),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.28),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _avatarColor,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withOpacity(0.32),
                                width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            widget.initials,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.isYou
                                    ? '${widget.fullName} (You)'
                                    : widget.fullName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                '@${widget.username}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(color: Color(0xFF2E3A4E), height: 1),
                    const SizedBox(height: 8),
                    _TooltipRow(
                      icon: Icons.shield_outlined,
                      label: 'Role',
                      text: _cap(widget.role),
                    ),
                    if (widget.department.trim().isNotEmpty)
                      _TooltipRow(
                        icon: Icons.business_outlined,
                        label: 'Dept',
                        text: widget.department,
                      ),
                    _TooltipRow(
                      icon: widget.isEditing
                          ? Icons.edit_outlined
                          : Icons.visibility_outlined,
                      label: 'Status',
                      text: widget.isEditing ? 'Editing' : 'Viewing',
                      highlight: widget.isEditing,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: Color(0xFF22C55E),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text(
                          'Online',
                          style: TextStyle(
                            fontSize: 10,
                            color: Color(0xFF86EFAC),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlay!);
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) {
        _hovered = true;
        _cursorGlobal = event.position;
        _scheduleShow();
      },
      onHover: (event) {
        _cursorGlobal = event.position;
        _overlay?.markNeedsBuild();
      },
      onExit: (_) {
        _hovered = false;
        _hideOverlay();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _hovered ? 1.04 : 1.0,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: widget.isYou
                  ? const Color(0xFF2563EB)
                  : (widget.isEditing ? const Color(0xFF22C55E) : Colors.white),
              width: widget.isYou ? 2.4 : 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isEditing
                    ? const Color(0x3322C55E)
                    : const Color(0x1A000000),
                blurRadius: 6,
                spreadRadius: widget.isEditing ? 0.5 : 0,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: CircleAvatar(
            backgroundColor: _avatarColor,
            backgroundImage: widget.avatarUrl.isNotEmpty
                ? NetworkImage(widget.avatarUrl)
                : null,
            child: widget.avatarUrl.isNotEmpty
                ? null
                : Text(
                    widget.initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Single row inside the hover tooltip card.
class _TooltipRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? label;
  final bool highlight;
  const _TooltipRow(
      {required this.icon,
      required this.text,
      this.label,
      this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 12,
              color:
                  highlight ? const Color(0xFF86EFAC) : Colors.grey.shade400),
          const SizedBox(width: 5),
          if (label != null) ...[
            Text('$label: ',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500)),
          ],
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                color:
                    highlight ? const Color(0xFF86EFAC) : Colors.grey.shade300,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
