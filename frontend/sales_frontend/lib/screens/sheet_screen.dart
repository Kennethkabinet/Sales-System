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
import '../widgets/app_modal.dart';
import 'inventory_template_seed.dart';

/// Sheet model for spreadsheet data
class SheetModel {
  final int id;
  final String name;
  final List<String> columns;
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> gridMeta;
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
    this.gridMeta = const <String, dynamic>{},
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
      gridMeta: json['grid_meta'] is Map
          ? Map<String, dynamic>.from(json['grid_meta'] as Map)
          : const <String, dynamic>{},
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
  final Map<int, double> columnWidths;
  final Map<int, double> rowHeights;
  final Set<int> hiddenColumns;
  final Set<int> hiddenRows;
  final Set<int> collapsedRows;

  // Grid metadata (formatting, borders, merged ranges)
  final Map<String, Set<String>> cellFormats;
  final Map<String, double> cellFontSizes;
  final Map<String, TextAlign> cellAlignments;
  final Map<String, Color> cellTextColors;
  final Map<String, Color> cellBackgroundColors;
  final Map<String, Map<String, bool>> cellBorders;
  final Set<String> mergedCellRanges;
  final double currentFontSize;
  final Color currentTextColor;
  final Color currentBackgroundColor;

  // Inventory Tracker header row heights (rows 1 & 2)
  final double invHeaderH1;
  final double invHeaderH2;

  const _SheetSnapshot({
    required this.columns,
    required this.data,
    required this.rowLabels,
    this.selectedRow,
    this.selectedCol,
    this.selectionEndRow,
    this.selectionEndCol,
    required this.columnWidths,
    required this.rowHeights,
    required this.hiddenColumns,
    required this.hiddenRows,
    required this.collapsedRows,
    required this.cellFormats,
    required this.cellFontSizes,
    required this.cellAlignments,
    required this.cellTextColors,
    required this.cellBackgroundColors,
    required this.cellBorders,
    required this.mergedCellRanges,
    required this.currentFontSize,
    required this.currentTextColor,
    required this.currentBackgroundColor,
    required this.invHeaderH1,
    required this.invHeaderH2,
  });
}

class SheetScreen extends StatefulWidget {
  final bool readOnly;
  final VoidCallback? onNavigateToEditRequests;
  final List<int>? initialFolderPath;
  final int? initialSheetId;
  final String? initialSheetName;
  final bool? initialSheetHasPassword;

  const SheetScreen({
    super.key,
    this.readOnly = false,
    this.onNavigateToEditRequests,
    this.initialFolderPath,
    this.initialSheetId,
    this.initialSheetName,
    this.initialSheetHasPassword,
  });

  @override
  State<SheetScreen> createState() => _SheetScreenState();
}

enum _InventorySortMode {
  normal,
  nameAsc,
  codeAsc,
  lowStockFirst,
  discrepancyFirst,
}

class _InventoryNoteSummary {
  final int discrepancyCount;
  final int commentCount;

  const _InventoryNoteSummary({
    required this.discrepancyCount,
    required this.commentCount,
  });

  bool get hasAny => discrepancyCount > 0 || commentCount > 0;
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

  // Pending deep-link navigation (folder-path then optional sheet)
  List<int> _pendingInitialFolderPathIds = [];
  int? _pendingInitialSheetId;
  String? _pendingInitialSheetName;
  bool? _pendingInitialSheetHasPassword;
  bool _deepLinkBusy = false;
  bool _deepLinkRerun = false;

  bool get _hasPendingDeepLink =>
      _pendingInitialFolderPathIds.isNotEmpty || _pendingInitialSheetId != null;

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

  // Display row numbering:
  // - Normal sheets: the column header is row 1 → first data row is 2.
  // - Inventory Tracker: the header is 2 rows tall → first data row is 3.
  static const int _kHeaderRowNumber = 1;

  // Inventory Tracker rows can be filtered/sorted without reordering `_data`.
  // Cache the *visible* display row number for each underlying row index so
  // that the row header, status bar cell reference, and edit-request
  // notifications stay consistent.
  final Map<int, int> _inventoryDisplayRowNumberByRowIndex = {};

  int _displayRowNumber(int rowIndex) {
    if (_isInventoryTrackerSheet()) {
      return _inventoryDisplayRowNumberByRowIndex[rowIndex] ?? (rowIndex + 3);
    }
    return rowIndex + 2;
  }

  String _defaultRowLabel(int rowIndex) => '${_displayRowNumber(rowIndex)}';
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

  bool _suppressFormulaBarChanged = false;

  // Live typing → real-time preview for other users (Socket.IO)
  Timer? _liveTypingDebounce;
  String _liveTypingLastSent = '';
  bool _suppressLiveTyping = false;

  // Auto-commit (persist) while typing to avoid conflicts
  Timer? _liveCommitDebounce;
  String _liveCommitLastSent = '';

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

  // Inventory Tracker note badges (Work Sheets landing + explorer)
  // Shows discrepancy notes (orange) or comment notes (blue).
  final Map<int, _InventoryNoteSummary> _inventoryNoteSummaryBySheetId = {};
  final Set<int> _inventoryNoteSummaryLoadingSheetIds = {};

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

  // Hide state for completely hidden columns/rows
  final Set<int> _hiddenColumns = {};
  final Set<int> _hiddenRows = {};

  // Row resize state (similar to column resize)
  bool _isResizingRow = false;
  int? _resizingRowIndex;
  double _resizingStartY = 0;
  double _resizingStartHeight = 0;
  static const double _minRowHeight = 20.0;
  static const double _maxRowHeight = 400.0;

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
  _InventorySortMode _inventorySortMode = _InventorySortMode.normal;
  double _criticalThreshold =
      0.80; // fraction used before red alert (default 80%)
  bool _invalidInventoryDialogOpen = false;
  String? _lastInvalidInventoryDialogKey;

  // Inventory Tracker performance: recomputing totals can scan all DATE columns,
  // and remote typing can arrive very frequently. Debounce/coalesce to keep the
  // UI responsive.
  final Map<int, Timer> _inventoryTotalsRecalcTimers = {};
  final Map<String, String> _pendingRemoteTypingCells = {};
  Timer? _pendingRemoteTypingFlush;
  int? _pendingRemoteTypingSheetId;

  // Inventory Tracker render performance:
  // The template can get very large (many products × many dates). Building every
  // row widget every frame (especially while scrolling) causes lag.
  //
  // We keep a cached, already-filtered/sorted row list and a prefix-sum of row
  // heights so we can virtualize row widgets (build only what is visible).
  bool _inventoryRowCacheDirty = true;
  bool _inventoryRowPrefixDirty = true;
  bool _inventoryColumnCacheDirty = true;

  bool _inventoryStockCountsDirty = true;
  int _inventoryCachedOutOfStockCount = 0;
  int _inventoryCachedCriticalCount = 0;
  int _inventoryCachedLowStockCount = 0;

  List<MapEntry<int, Map<String, String>>> _inventoryCachedEntries =
      const <MapEntry<int, Map<String, String>>>[];
  List<double> _inventoryCachedRowPrefixHeights = const <double>[]; // len = n+1
  double _inventoryCachedDataRowsHeight = 0.0;

  List<String> _inventoryCachedVisibleColumnKeys = const <String>[];
  List<double> _inventoryCachedColPrefixWidths = const <double>[]; // len = m+1
  double _inventoryCachedTotalWidth = 0.0;
  final Map<String, int> _inventoryCachedColIndexByKey = <String, int>{};

  void _invalidateInventoryRowCache({bool prefixOnly = false}) {
    if (!_isInventoryTrackerSheet()) return;
    if (!prefixOnly) {
      _inventoryRowCacheDirty = true;
    }
    _inventoryRowPrefixDirty = true;
    _inventoryStockCountsDirty = true;
  }

  void _invalidateInventoryColumnCache() {
    if (!_isInventoryTrackerSheet()) return;
    _inventoryColumnCacheDirty = true;
    _inventoryStockCountsDirty = true;
  }

  void _recomputeInventoryStockCounts() {
    final productKey = _inventoryProductNameKey();
    final totalKey = _inventoryTotalQtyKey();

    double? numVal(Map<String, String> row, String? key) {
      if (key == null) return null;
      final raw = (row[key] ?? '').replaceAll(',', '').trim();
      if (raw.isEmpty) return null;
      return double.tryParse(raw);
    }

    int outOfStock = 0;
    int critical = 0;
    int lowStock = 0;

    for (final entry in _inventoryCachedEntries) {
      final row = entry.value;

      final productName =
          (productKey == null ? '' : (row[productKey] ?? '')).trim();
      final code = _inventoryRowCode(row).trim();
      if (productName.isEmpty && code.isEmpty) continue;

      final totalQty = numVal(row, totalKey);
      final isOut = totalQty != null && totalQty <= 0;
      if (isOut) {
        outOfStock++;
        continue;
      }

      final isCritical = _criticalDeficitPctForRow(row) != null;
      if (isCritical) {
        critical++;
        continue;
      }

      final isLow = _maintainingDeficitPctForRow(row) != null;
      if (isLow) {
        lowStock++;
      }
    }

    _inventoryCachedOutOfStockCount = outOfStock;
    _inventoryCachedCriticalCount = critical;
    _inventoryCachedLowStockCount = lowStock;
    _inventoryStockCountsDirty = false;
  }

  void _ensureInventoryRowCache() {
    if (!_isInventoryTrackerSheet()) return;

    if (_inventoryRowCacheDirty) {
      final entries = _inventoryFilteredEntries();
      _inventoryCachedEntries = entries;

      // Update display row number mapping once per cache build (not per scroll).
      _inventoryDisplayRowNumberByRowIndex.clear();
      for (int i = 0; i < entries.length; i++) {
        _inventoryDisplayRowNumberByRowIndex[entries[i].key] = i + 3;
      }

      _inventoryRowCacheDirty = false;
      _inventoryRowPrefixDirty = true;
    }

    if (_inventoryRowPrefixDirty) {
      final prefix = <double>[0.0];
      for (final entry in _inventoryCachedEntries) {
        prefix.add(prefix.last + _getRowHeight(entry.key));
      }
      _inventoryCachedRowPrefixHeights = prefix;
      _inventoryCachedDataRowsHeight = prefix.isEmpty ? 0.0 : prefix.last;
      _inventoryRowPrefixDirty = false;
    }

    if (_inventoryStockCountsDirty) {
      _recomputeInventoryStockCounts();
    }
  }

  static int _lowerBoundDouble(List<double> a, double x) {
    int lo = 0;
    int hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  static int _upperBoundDouble(List<double> a, double x) {
    int lo = 0;
    int hi = a.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (a[mid] <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  String _inventorySortLabel(_InventorySortMode mode) {
    switch (mode) {
      case _InventorySortMode.normal:
        return 'Normal';
      case _InventorySortMode.nameAsc:
        return 'A–Z';
      case _InventorySortMode.codeAsc:
        return 'Code A–Z';
      case _InventorySortMode.lowStockFirst:
        return 'Low Stock';
      case _InventorySortMode.discrepancyFirst:
        return 'Discrepancy';
    }
  }

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

  void _clearGridMetaState() {
    _cellFormats.clear();
    _cellFontSizes.clear();
    _cellAlignments.clear();
    _cellTextColors.clear();
    _cellBackgroundColors.clear();
    _cellBorders.clear();
    _mergedCellRanges.clear();
  }

  static String _normGridMetaKey(String k) {
    return k.replaceAll('_', '').toLowerCase();
  }

  static Map<String, dynamic>? _readMetaMap(
      Map<String, dynamic> meta, String key) {
    final target = _normGridMetaKey(key);
    for (final entry in meta.entries) {
      if (_normGridMetaKey(entry.key) == target && entry.value is Map) {
        return Map<String, dynamic>.from(entry.value as Map);
      }
    }
    return null;
  }

  static List<dynamic>? _readMetaList(Map<String, dynamic> meta, String key) {
    final target = _normGridMetaKey(key);
    for (final entry in meta.entries) {
      if (_normGridMetaKey(entry.key) == target && entry.value is List) {
        return List<dynamic>.from(entry.value as List);
      }
    }
    return null;
  }

  static TextAlign? _decodeTextAlign(dynamic v) {
    if (v == null) return null;
    final s = v.toString().toLowerCase().trim();
    if (s == 'left') return TextAlign.left;
    if (s == 'center') return TextAlign.center;
    if (s == 'right') return TextAlign.right;
    return null;
  }

  static String _encodeTextAlign(TextAlign a) {
    switch (a) {
      case TextAlign.left:
        return 'left';
      case TextAlign.center:
        return 'center';
      case TextAlign.right:
        return 'right';
      default:
        return 'left';
    }
  }

  static Color? _decodeColor(dynamic v) {
    if (v == null) return null;
    if (v is int) return Color(v);
    if (v is num) return Color(v.toInt());
    final s = v.toString().trim();
    final hex = s.startsWith('0x') ? s.substring(2) : s;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return Color(parsed);
  }

  static int _encodeColor(Color c) => c.toARGB32();

  void _applyGridMetaFromSheet(SheetModel sheet, {Map<int, int>? colIndexMap}) {
    _clearGridMetaState();
    final meta = sheet.gridMeta;
    if (meta.isEmpty) return;

    String? remapCellKey(String key) {
      if (colIndexMap == null) return key;
      final parts = key.split(',');
      if (parts.length != 2) return null;
      final r = int.tryParse(parts[0]);
      final c = int.tryParse(parts[1]);
      if (r == null || c == null) return null;
      final mapped = colIndexMap[c];
      if (mapped == null) return null;
      return '$r,$mapped';
    }

    String? remapRangeKey(String rangeKey) {
      if (colIndexMap == null) return rangeKey;
      final parts = rangeKey.split(':');
      if (parts.length != 2) return null;
      final start = parts[0].split(',');
      final end = parts[1].split(',');
      if (start.length != 2 || end.length != 2) return null;
      final minRow = int.tryParse(start[0]);
      final minCol = int.tryParse(start[1]);
      final maxRow = int.tryParse(end[0]);
      final maxCol = int.tryParse(end[1]);
      if (minRow == null ||
          minCol == null ||
          maxRow == null ||
          maxCol == null) {
        return null;
      }
      final mappedMin = colIndexMap[minCol];
      final mappedMax = colIndexMap[maxCol];
      if (mappedMin == null || mappedMax == null) return null;
      final newMinCol = mappedMin < mappedMax ? mappedMin : mappedMax;
      final newMaxCol = mappedMin < mappedMax ? mappedMax : mappedMin;
      return '$minRow,$newMinCol:$maxRow,$newMaxCol';
    }

    try {
      final fmts = _readMetaMap(meta, 'cellFormats');
      if (fmts != null) {
        for (final e in fmts.entries) {
          if (e.value is List) {
            final k = remapCellKey(e.key);
            if (k == null) continue;
            final list = (e.value as List)
                .map((v) => v.toString().trim())
                .where((v) => v.isNotEmpty)
                .toList();
            if (list.isNotEmpty) {
              _cellFormats[k] = Set<String>.from(list);
            }
          }
        }
      }

      final fontSizes = _readMetaMap(meta, 'cellFontSizes');
      if (fontSizes != null) {
        for (final e in fontSizes.entries) {
          final k = remapCellKey(e.key);
          if (k == null) continue;
          final n = (e.value is num)
              ? (e.value as num).toDouble()
              : double.tryParse(e.value.toString());
          if (n != null) _cellFontSizes[k] = n;
        }
      }

      final aligns = _readMetaMap(meta, 'cellAlignments');
      if (aligns != null) {
        for (final e in aligns.entries) {
          final k = remapCellKey(e.key);
          if (k == null) continue;
          final a = _decodeTextAlign(e.value);
          if (a != null) _cellAlignments[k] = a;
        }
      }

      final textColors = _readMetaMap(meta, 'cellTextColors');
      if (textColors != null) {
        for (final e in textColors.entries) {
          final k = remapCellKey(e.key);
          if (k == null) continue;
          final c = _decodeColor(e.value);
          if (c != null) _cellTextColors[k] = c;
        }
      }

      final bgColors = _readMetaMap(meta, 'cellBackgroundColors');
      if (bgColors != null) {
        for (final e in bgColors.entries) {
          final k = remapCellKey(e.key);
          if (k == null) continue;
          final c = _decodeColor(e.value);
          if (c != null) _cellBackgroundColors[k] = c;
        }
      }

      final borders = _readMetaMap(meta, 'cellBorders');
      if (borders != null) {
        for (final e in borders.entries) {
          if (e.value is Map) {
            final k = remapCellKey(e.key);
            if (k == null) continue;
            final m = Map<String, dynamic>.from(e.value as Map);
            _cellBorders[k] = {
              'top': m['top'] == true,
              'right': m['right'] == true,
              'bottom': m['bottom'] == true,
              'left': m['left'] == true,
            };
          }
        }
      }

      final merged = _readMetaList(meta, 'mergedCellRanges');
      if (merged != null) {
        for (final v in merged) {
          final s = v.toString().trim();
          if (s.isEmpty) continue;
          final rk = remapRangeKey(s);
          if (rk != null && rk.trim().isNotEmpty) {
            _mergedCellRanges.add(rk);
          }
        }
      }
    } catch (_) {
      // Ignore malformed meta; keep the sheet usable.
    }
  }

  Map<String, dynamic> _buildGridMetaForSave() {
    final meta = <String, dynamic>{};

    if (_cellFormats.isNotEmpty) {
      meta['cellFormats'] = _cellFormats.map((k, v) => MapEntry(k, v.toList()));
    }
    if (_cellFontSizes.isNotEmpty) {
      meta['cellFontSizes'] = Map<String, double>.from(_cellFontSizes);
    }
    if (_cellAlignments.isNotEmpty) {
      meta['cellAlignments'] =
          _cellAlignments.map((k, v) => MapEntry(k, _encodeTextAlign(v)));
    }
    if (_cellTextColors.isNotEmpty) {
      meta['cellTextColors'] =
          _cellTextColors.map((k, v) => MapEntry(k, _encodeColor(v)));
    }
    if (_cellBackgroundColors.isNotEmpty) {
      meta['cellBackgroundColors'] =
          _cellBackgroundColors.map((k, v) => MapEntry(k, _encodeColor(v)));
    }
    if (_cellBorders.isNotEmpty) {
      meta['cellBorders'] =
          _cellBorders.map((k, v) => MapEntry(k, Map<String, bool>.from(v)));
    }
    if (_mergedCellRanges.isNotEmpty) {
      meta['mergedCellRanges'] = _mergedCellRanges.toList();
    }

    return meta;
  }

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

    // Configure any incoming deep-link before initial load.
    _pendingInitialFolderPathIds =
        List<int>.from(widget.initialFolderPath ?? <int>[]);
    _pendingInitialSheetId = widget.initialSheetId;
    _pendingInitialSheetName = widget.initialSheetName;
    _pendingInitialSheetHasPassword = widget.initialSheetHasPassword;
    if (_hasPendingDeepLink) {
      _sheetFolderBreadcrumbs = [];
      _currentSheetFolderId = null;
      _currentSheetFolderName = null;
    }

    _initializeSheet();
    _loadSheets();
    _setupSheetPresenceCallbacks();

    // Emit live typing updates while editing a cell.
    _editController.addListener(_onLocalEditControllerChanged);

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

  @override
  void didUpdateWidget(covariant SheetScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath = oldWidget.initialFolderPath ?? <int>[];
    final newPath = widget.initialFolderPath ?? <int>[];
    final pathChanged = !listEquals(oldPath, newPath);
    final sheetChanged = widget.initialSheetId != oldWidget.initialSheetId ||
        widget.initialSheetName != oldWidget.initialSheetName ||
        widget.initialSheetHasPassword != oldWidget.initialSheetHasPassword;

    if (!pathChanged && !sheetChanged) return;

    _pendingInitialFolderPathIds = List<int>.from(newPath);
    _pendingInitialSheetId = widget.initialSheetId;
    _pendingInitialSheetName = widget.initialSheetName;
    _pendingInitialSheetHasPassword = widget.initialSheetHasPassword;

    if (_hasPendingDeepLink) {
      setState(() {
        _sheetFolderBreadcrumbs.clear();
        _currentSheetFolderId = null;
        _currentSheetFolderName = null;
      });
      _loadSheets();
    }
  }

  void _scheduleDeepLinkProcessing() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _processPendingDeepLink();
    });
  }

  Future<void> _processPendingDeepLink() async {
    if (!mounted) return;
    if (_isLoading) return;
    if (!_hasPendingDeepLink) return;

    if (_deepLinkBusy) {
      _deepLinkRerun = true;
      return;
    }

    _deepLinkBusy = true;
    try {
      // Step 1: walk the folder path from root, one level at a time.
      if (_pendingInitialFolderPathIds.isNotEmpty) {
        final nextFolderId = _pendingInitialFolderPathIds.first;
        final folder = _sheetFolders
            .cast<Map<String, dynamic>>()
            .where((f) => f['id'] == nextFolderId)
            .cast<Map<String, dynamic>>()
            .toList(growable: false);

        if (folder.isEmpty) {
          // Folder not visible at this level (or no longer exists).
          _pendingInitialFolderPathIds.clear();
          _pendingInitialSheetId = null;
          return;
        }

        _pendingInitialFolderPathIds = _pendingInitialFolderPathIds.sublist(1);
        final beforeFolderId = _currentSheetFolderId;
        await _openFolderWithPasswordCheck(folder.first);
        if (!mounted) return;

        // If navigation did not happen (cancel/incorrect password), abort.
        if (_currentSheetFolderId == beforeFolderId) {
          _pendingInitialFolderPathIds.clear();
          _pendingInitialSheetId = null;
        }
        return;
      }

      // Step 2: open the sheet (if provided) after folder navigation completes.
      if (_pendingInitialSheetId != null) {
        final stub = SheetModel(
          id: _pendingInitialSheetId!,
          name: _pendingInitialSheetName ?? 'Sheet',
          hasPassword: _pendingInitialSheetHasPassword ?? false,
        );
        _pendingInitialSheetId = null;
        await _openSheetWithPasswordCheck(stub);
      }
    } finally {
      _deepLinkBusy = false;
      if (_deepLinkRerun) {
        _deepLinkRerun = false;
        _scheduleDeepLinkProcessing();
      }
    }
  }

  // =============== Collaborative Editing Features ===============

  /// Toggle sheet visibility to viewers (Admin only)
  Future<void> _toggleSheetVisibility(int sheetId, bool showToViewers) async {
    try {
      await ApiService.toggleSheetVisibility(sheetId, showToViewers);
      await _loadSheets(); // Refresh sheets list
      await _refreshSheetStatus(); // Refresh current sheet status

      if (mounted) {
        AppModal.showText(
          context,
          title: 'Success',
          message: showToViewers
              ? 'Sheet is now visible to viewers'
              : 'Sheet is now hidden from viewers',
        );
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to update visibility: $e',
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
          AppModal.showText(
            context,
            title: 'Success',
            message: newPw.isEmpty ? 'Password removed' : 'Password set',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed: $e',
        );
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
          AppModal.showText(
            context,
            title: 'Success',
            message: newPw.isEmpty ? 'Password removed' : 'Password set',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed: $e',
        );
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
          AppModal.showText(
            context,
            title: 'Error',
            message: 'Incorrect password',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Incorrect password',
        );
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
          AppModal.showText(
            context,
            title: 'Error',
            message: 'Incorrect password',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Incorrect password',
        );
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
        AppModal.showText(
          context,
          title: 'Notice',
          message: 'Sheet locked for editing',
        );
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to lock sheet: $e',
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
        AppModal.showText(
          context,
          title: 'Success',
          message: 'Sheet unlocked',
        );
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to unlock sheet: $e',
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

      // Show one-time notice when a different user locks the sheet
      if (mounted && _isLocked && _lockedByUser != null) {
        final authProvider = Provider.of<AuthProvider>(context, listen: false);
        final currentUsername = authProvider.user?.username ?? '';
        if (_lockedByUser != currentUsername &&
            _lastShownLockUser != _lockedByUser) {
          _lastShownLockUser = _lockedByUser;
          AppModal.showText(
            context,
            title: 'Notice',
            message: '$_lockedByUser is currently editing this sheet',
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
    _rowLabels = List.generate(100, (index) => _defaultRowLabel(index));
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

      // Prefetch discrepancy badges for visible Inventory Tracker sheets.
      _prefetchInventoryNoteBadges(_sheets);

      if (_hasPendingDeepLink) {
        _scheduleDeepLinkProcessing();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  bool _isInventoryTrackerColumns(List<String> columns) {
    bool hasInvId(String id) {
      for (final c in columns) {
        if (_invColumnId(c) == id) return true;
      }
      return false;
    }

    final hasProduct = columns.contains('Material Name') ||
        columns.contains('Product Name') ||
        hasInvId('product_name');
    final hasCode = columns.contains('QB Code') ||
        columns.contains('QC Code') ||
        hasInvId('code');
    final hasStock = columns.contains('Stock') || hasInvId('stock');
    final hasTotal =
        columns.contains('Total Quantity') || hasInvId('total_qty');
    return hasProduct && hasCode && (hasStock || hasTotal);
  }

  Widget _buildInventoryNoteBadge(
    _InventoryNoteSummary summary, {
    double fontSize = 10,
    String? tooltipOverride,
  }) {
    final bool isDiscrepancy = summary.discrepancyCount > 0;
    final bool isCommentOnly = !isDiscrepancy && summary.commentCount > 0;

    final int shownCount =
        isDiscrepancy ? summary.discrepancyCount : summary.commentCount;
    final label = shownCount > 99 ? '99+' : '$shownCount';
    final Color bg = isDiscrepancy
        ? AppColors.primaryOrange
        : (isCommentOnly ? AppColors.primaryBlue : AppColors.primaryOrange);

    final tooltipLines = <String>[];
    if (summary.discrepancyCount > 0) {
      tooltipLines.add('Discrepancy notes: ${summary.discrepancyCount}');
    }
    if (summary.commentCount > 0) {
      tooltipLines.add('Comments: ${summary.commentCount}');
    }
    final tooltip = tooltipOverride ??
        (tooltipLines.isEmpty ? 'No notes' : tooltipLines.join('\n'));

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.0,
          ),
        ),
      ),
    );
  }

  void _prefetchInventoryNoteBadges(List<SheetModel> sheets) {
    for (final s in sheets) {
      _ensureInventoryNoteSummaryLoaded(s);
    }
  }

  void _ensureInventoryNoteSummaryLoaded(SheetModel sheet) {
    if (_inventoryNoteSummaryBySheetId.containsKey(sheet.id)) return;
    if (_inventoryNoteSummaryLoadingSheetIds.contains(sheet.id)) return;

    // Only Inventory Tracker sheets can have discrepancy/comment notes.
    if (!_isInventoryTrackerColumns(sheet.columns)) {
      _inventoryNoteSummaryBySheetId[sheet.id] =
          const _InventoryNoteSummary(discrepancyCount: 0, commentCount: 0);
      return;
    }

    _inventoryNoteSummaryLoadingSheetIds.add(sheet.id);
    unawaited(_loadInventoryNoteSummary(sheet.id));
  }

  Future<void> _loadInventoryNoteSummary(int sheetId) async {
    try {
      final resp = await ApiService.getSheetData(sheetId);
      if (!mounted) return;

      final sheet = SheetModel.fromJson(resp['sheet']);
      if (!_isInventoryTrackerColumns(sheet.columns)) {
        setState(() {
          _inventoryNoteSummaryBySheetId[sheetId] =
              const _InventoryNoteSummary(discrepancyCount: 0, commentCount: 0);
        });
        return;
      }

      final cols = sheet.columns;
      final bool hasEncodedInventoryCols = cols.any(_isInvEncodedColumnKey);

      String? findColById(String id) {
        for (final c in cols) {
          if (_invColumnId(c) == id) return c;
        }
        return null;
      }

      final commentKey = hasEncodedInventoryCols
          ? (findColById('comment') ??
              _invEncodeColKey('comment', _kInventoryCommentCol))
          : _kInventoryCommentCol;
      final typeKey = hasEncodedInventoryCols
          ? (findColById('note_type') ??
              _invEncodeColKey('note_type', _kInventoryNoteTypeCol))
          : _kInventoryNoteTypeCol;
      final titleKey = hasEncodedInventoryCols
          ? (findColById('note_title') ??
              _invEncodeColKey('note_title', _kInventoryNoteTitleCol))
          : _kInventoryNoteTitleCol;

      int discrepancyCount = 0;
      int commentCount = 0;
      for (final r in sheet.rows) {
        final body = (r[commentKey] ?? '').toString().trim();
        final title = (r[titleKey] ?? '').toString().trim();
        final hasNote = body.isNotEmpty || title.isNotEmpty;
        if (!hasNote) continue;

        final rawType = (r[typeKey] ?? '').toString().trim();
        final type = rawType.toLowerCase();

        // Legacy notes (no type saved) are treated as discrepancy.
        if (type.isEmpty || type == _kInventoryNoteTypeDiscrepancy) {
          discrepancyCount += 1;
        } else {
          commentCount += 1;
        }
      }

      if (!mounted) return;
      setState(() {
        _inventoryNoteSummaryBySheetId[sheetId] = _InventoryNoteSummary(
          discrepancyCount: discrepancyCount,
          commentCount: commentCount,
        );
      });
    } catch (_) {
      // Keep silent; no badge is better than breaking list rendering.
      if (!mounted) return;
      setState(() {
        _inventoryNoteSummaryBySheetId[sheetId] =
            const _InventoryNoteSummary(discrepancyCount: 0, commentCount: 0);
      });
    } finally {
      _inventoryNoteSummaryLoadingSheetIds.remove(sheetId);
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

    bool migratedInventoryMaintaining = false;

    try {
      final response = await ApiService.getSheetData(sheetId);
      if (!mounted) return;
      final sheet = SheetModel.fromJson(response['sheet']);
      final serverColumns = sheet.columns.isNotEmpty
          ? List<String>.from(sheet.columns)
          : <String>['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'];

      setState(() {
        _currentSheet = sheet;
        _columns = List<String>.from(serverColumns);

        // Inventory Tracker grid caches depend on columns/data.
        _inventoryRowCacheDirty = true;
        _inventoryRowPrefixDirty = true;
        _inventoryColumnCacheDirty = true;

        // Inventory Tracker: always start in the normal (default) ordering
        // when opening the template/sheet.
        if (_isInventoryTrackerSheet()) {
          _inventorySortMode = _InventorySortMode.normal;
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
        if (_isInventoryTrackerSheet()) {
          final bool hasEncodedInventoryCols =
              _columns.any(_isInvEncodedColumnKey);

          ({bool migrated}) migrateIdentifierHeaders() {
            bool did = false;

            void renameKey(String oldKey, String newKey) {
              if (oldKey == newKey) return;
              if (!_columns.contains(oldKey)) return;
              if (_columns.contains(newKey)) return;
              final idx = _columns.indexOf(oldKey);
              if (idx < 0) return;
              _columns[idx] = newKey;
              for (final row in _data) {
                if (row.containsKey(oldKey) && !row.containsKey(newKey)) {
                  row[newKey] = row[oldKey] ?? '';
                }
                row.remove(oldKey);
              }
              did = true;
            }

            if (hasEncodedInventoryCols) {
              final prodKey = _findInvColKeyById('product_name');
              if (prodKey != null &&
                  _invColumnDisplay(prodKey) == 'Product Name') {
                renameKey(
                    prodKey, _invEncodeColKey('product_name', 'Material Name'));
              }
              final codeKey = _findInvColKeyById('code');
              if (codeKey != null && _invColumnDisplay(codeKey) == 'QC Code') {
                renameKey(codeKey, _invEncodeColKey('code', 'QB Code'));
              }
            } else {
              renameKey('Product Name', 'Material Name');
              renameKey('QC Code', 'QB Code');
            }

            return (migrated: did);
          }

          final idMig = migrateIdentifierHeaders();
          if (idMig.migrated) migratedInventoryMaintaining = true;

          final commentCol = hasEncodedInventoryCols
              ? (_findInvColKeyById('comment') ??
                  _invEncodeColKey('comment', _kInventoryCommentCol))
              : _kInventoryCommentCol;
          final noteTypeCol = hasEncodedInventoryCols
              ? (_findInvColKeyById('note_type') ??
                  _invEncodeColKey('note_type', _kInventoryNoteTypeCol))
              : _kInventoryNoteTypeCol;
          final noteTitleCol = hasEncodedInventoryCols
              ? (_findInvColKeyById('note_title') ??
                  _invEncodeColKey('note_title', _kInventoryNoteTitleCol))
              : _kInventoryNoteTitleCol;

          // If a legacy Remarks column exists, preserve it by migrating its
          // content into Comment before stripping.
          for (final row in _data) {
            final legacyRemarks = (row['Remarks'] ?? '').trim();
            final existing = (row[commentCol] ?? '').trim();
            if (legacyRemarks.isNotEmpty && existing.isEmpty) {
              row[commentCol] = legacyRemarks;
            }
          }

          const legacy = ['Reference No.', 'Remarks', 'Date', 'IN', 'OUT'];
          for (final col in legacy) {
            _columns.remove(col);
            for (final row in _data) {
              row.remove(col);
            }
          }

          // Load persisted grid metadata (formatting, borders, merged ranges, etc.).
          // If we stripped legacy columns, remap server indices to the new indices.
          final colIndexMap = <int, int>{};
          for (int newIdx = 0; newIdx < _columns.length; newIdx++) {
            final oldIdx = serverColumns.indexOf(_columns[newIdx]);
            if (oldIdx >= 0) colIndexMap[oldIdx] = newIdx;
          }
          _applyGridMetaFromSheet(sheet,
              colIndexMap: colIndexMap.isEmpty ? null : colIndexMap);
          // Ensure Inventory Tracker has dedicated note columns.
          if (!_columns.contains(commentCol) ||
              !_columns.contains(noteTypeCol) ||
              !_columns.contains(noteTitleCol)) {
            final productKey = _inventoryProductNameKey();
            final anchor =
                productKey != null ? _columns.indexOf(productKey) : -1;
            int insertAt = anchor >= 0 ? (anchor + 1) : 1;

            if (!_columns.contains(commentCol)) {
              _columns.insert(insertAt.clamp(0, _columns.length), commentCol);
            }
            final commentIdx = _columns.indexOf(commentCol);
            insertAt = commentIdx >= 0 ? (commentIdx + 1) : insertAt;

            if (!_columns.contains(noteTypeCol)) {
              _columns.insert(insertAt.clamp(0, _columns.length), noteTypeCol);
            }
            final typeIdx = _columns.indexOf(noteTypeCol);
            insertAt = typeIdx >= 0 ? (typeIdx + 1) : insertAt;

            if (!_columns.contains(noteTitleCol)) {
              _columns.insert(insertAt.clamp(0, _columns.length), noteTitleCol);
            }
          }

          for (final row in _data) {
            row.putIfAbsent(commentCol, () => '');
            row.putIfAbsent(noteTypeCol, () => '');
            row.putIfAbsent(noteTitleCol, () => '');

            // Backfill type for legacy notes.
            final body = (row[commentCol] ?? '').trim();
            final title = (row[noteTitleCol] ?? '').trim();
            final rawType = (row[noteTypeCol] ?? '').trim();
            if ((body.isNotEmpty || title.isNotEmpty) && rawType.isEmpty) {
              row[noteTypeCol] = _kInventoryNoteTypeDiscrepancy;
            }
          }

          // Ensure modern Inventory Tracker has a dedicated Stock column.
          final totalKey = _inventoryTotalQtyKey();
          final existingStockKey = _inventoryStockKey();
          if (existingStockKey == null) {
            final stockCol = hasEncodedInventoryCols
                ? (_findInvColKeyById('stock') ??
                    _invEncodeColKey('stock', 'Stock'))
                : 'Stock';
            final maintainingIdx = _columns.indexOf('Maintaining');
            final insertAt = maintainingIdx >= 0 ? maintainingIdx : 2;
            _columns.insert(insertAt, stockCol);
            for (final row in _data) {
              final current =
                  (totalKey == null ? '' : (row[totalKey] ?? '')).trim();
              row[stockCol] = current.isEmpty ? '0' : current;
            }
          }

          // Migrate legacy "Maintaining" into split columns:
          // - Maintaining Qty (number) OR "-" when per-request
          // - Maintaining Unit (text)  OR "PR" when per-request
          ({bool migrated}) migrateMaintaining() {
            String norm(String v) => v.trim();

            ({String qty, String unit}) parseLegacy(String raw) {
              final t = norm(raw);
              if (t.isEmpty) return (qty: '', unit: '');
              final lower = t.toLowerCase();
              if (lower == 'pr' ||
                  lower == 'per request' ||
                  lower == 'per-request') {
                return (qty: '-', unit: 'PR');
              }

              // Try parse leading number, rest = unit.
              final cleaned = t.replaceAll(',', '');
              final m = RegExp(r'^(-?\d+(?:\.\d+)?)(?:\s+(.+))?$')
                  .firstMatch(cleaned);
              if (m == null) return (qty: '', unit: '');
              final qty = (m.group(1) ?? '').trim();
              final unit = (m.group(2) ?? '').trim();
              return (qty: qty, unit: unit);
            }

            bool did = false;
            final existingQtyKey = _inventoryMaintainingQtyKey();
            final existingUnitKey = _inventoryMaintainingUnitKey();
            final qtyCol = existingQtyKey ??
                (hasEncodedInventoryCols
                    ? _invEncodeColKey('maintaining_qty', 'Maintaining Qty')
                    : 'Maintaining Qty');
            final unitCol = existingUnitKey ??
                (hasEncodedInventoryCols
                    ? _invEncodeColKey('maintaining_unit', 'Maintaining Unit')
                    : 'Maintaining Unit');

            // Add split columns if missing.
            if (!_columns.contains(qtyCol) || !_columns.contains(unitCol)) {
              // Insert after Stock if possible, else after code column.
              final resolvedStockKey = _inventoryStockKey();
              final stockIdx = resolvedStockKey == null
                  ? -1
                  : _columns.indexOf(resolvedStockKey);
              final insertAt = stockIdx >= 0 ? stockIdx + 1 : 2;
              if (!_columns.contains(qtyCol)) {
                _columns.insert(insertAt, qtyCol);
                did = true;
              }
              final unitIdx = _columns.indexOf(qtyCol);
              if (!_columns.contains(unitCol)) {
                _columns.insert(
                    unitIdx >= 0 ? unitIdx + 1 : insertAt + 1, unitCol);
                did = true;
              }
              for (final row in _data) {
                row.putIfAbsent(qtyCol, () => '');
                row.putIfAbsent(unitCol, () => '');
              }
            }

            // Populate split columns from legacy Maintaining when available.
            for (final row in _data) {
              final legacy = (row['Maintaining'] ?? '').toString();
              if (legacy.trim().isEmpty) continue;
              final alreadyHas = (row[qtyCol] ?? '').trim().isNotEmpty ||
                  (row[unitCol] ?? '').trim().isNotEmpty;
              if (alreadyHas) continue;

              final parsed = parseLegacy(legacy);
              row[qtyCol] = parsed.qty;
              row[unitCol] = parsed.unit;
              did = true;
            }

            // Back-compat: if there is a Maintaining Status column, fold PR into unit/qty.
            if (_columns.contains('Maintaining Status')) {
              for (final row in _data) {
                final status =
                    (row['Maintaining Status'] ?? '').trim().toUpperCase();
                if (status == 'PR') {
                  row[qtyCol] = '-';
                  row[unitCol] = 'PR';
                  did = true;
                }
                row.remove('Maintaining Status');
              }
              _columns.remove('Maintaining Status');
              did = true;
            }

            // Remove legacy Maintaining column to avoid mixed values.
            if (_columns.contains('Maintaining')) {
              _columns.remove('Maintaining');
              for (final row in _data) {
                row.remove('Maintaining');
              }
              did = true;
            }

            return (migrated: did);
          }

          final mig = migrateMaintaining();
          if (mig.migrated) migratedInventoryMaintaining = true;

          // Ensure Inventory Tracker has a dedicated Critical threshold column.
          final existingCriticalKey = _inventoryCriticalKey();
          if (existingCriticalKey == null) {
            final qtyKey = _inventoryMaintainingQtyKey();
            final unitKey = _inventoryMaintainingUnitKey();
            final criticalCol = hasEncodedInventoryCols
                ? (_findInvColKeyById('critical') ??
                    _invEncodeColKey('critical', 'Critical'))
                : 'Critical';

            final unitIdx = unitKey == null ? -1 : _columns.indexOf(unitKey);
            final qtyIdx = qtyKey == null ? -1 : _columns.indexOf(qtyKey);
            final anchor = unitIdx >= 0 ? unitIdx : (qtyIdx >= 0 ? qtyIdx : 3);
            _columns.insert(anchor + 1, criticalCol);
            for (final row in _data) {
              final qtyRaw = (qtyKey == null ? '' : (row[qtyKey] ?? ''))
                  .replaceAll(',', '')
                  .trim();
              final qty = double.tryParse(qtyRaw) ?? 0;
              final unit = (unitKey == null ? '' : (row[unitKey] ?? ''))
                  .trim()
                  .toUpperCase();
              final isPr = unit == 'PR' || qtyRaw == '-';
              row[criticalCol] =
                  (isPr || qty <= 0) ? '0' : qty.toStringAsFixed(0);
            }
            migratedInventoryMaintaining = true;
          }
        }

        // Reset row labels to match data length
        _rowLabels =
            List.generate(_data.length, (index) => _defaultRowLabel(index));

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

      // Persist the migration so exports/imports stay consistent.
      if (migratedInventoryMaintaining && mounted && _canEditSheet()) {
        _markDirty();
      }
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

  void _startSheetCollaboration(int sheetId) {
    // Announce presence in this sheet room via socket.
    SocketService.instance.joinSheet(sheetId);
    _heartbeatAndFetchActiveUsers();

    // Request the full presence list immediately, then retry at increasing
    // intervals to self-heal any missed events.
    for (final ms in const [0, 300, 800, 2000, 5000]) {
      Future.delayed(Duration(milliseconds: ms), () {
        if (mounted && _currentSheet?.id == sheetId) {
          SocketService.instance.getPresence(sheetId);
        }
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
        _rowLabels = List.generate(100, (index) => _defaultRowLabel(index));
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

      // Refresh collaborative editing status and join the sheet room so
      // real-time updates work immediately for newly created sheets.
      unawaited(_refreshSheetStatus());
      if (_currentSheet != null) {
        _startSheetCollaboration(_currentSheet!.id);
      }

      // Keep dashboard context in sync.
      if (mounted) {
        context.read<DataProvider>().setCurrentSheet(
              sheetId: sheet.id,
              sheetName: sheet.name,
            );
        context.read<DataProvider>().loadInventorySheets();
      }

      if (mounted) {
        AppModal.showText(
          context,
          title: 'Success',
          message: 'New sheet created',
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to create sheet: $e',
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  Sheet Templates
  // ════════════════════════════════════════════

  /// All built-in templates available for sheet creation
  static final List<Map<String, dynamic>> _kTemplates = [
    {
      'id': 'inventory_tracker',
      'name': 'Inventory Tracker',
      'description':
          'Product inventory with daily IN/OUT transactions, stock thresholds, and running totals.',
      'iconData': 0xe1d1, // Icons.inventory codepoint
      'colorValue': 0xFF1E3A6E,
      'columns': [
        'Material Name',
        'Comment',
        'Note Type',
        'Note Title',
        'QB Code',
        'Stock',
        'Maintaining Qty',
        'Maintaining Unit',
        'Critical',
        'Total Quantity',
      ],
      'rows': kInventoryTrackerSeedRows,
    },
    {
      'id': 'inventory_tracker_empty',
      'name': 'Inventory Tracker (Empty)',
      'description':
          'Blank inventory tracker with no pre-filled items (start from scratch).',
      'iconData': 0xe1d1, // Icons.inventory codepoint
      'colorValue': 0xFF1E3A6E,
      'columns': [
        'Material Name',
        'Comment',
        'Note Type',
        'Note Title',
        'QB Code',
        'Stock',
        'Maintaining Qty',
        'Maintaining Unit',
        'Critical',
        'Total Quantity',
      ],
      'rows': const <Map<String, dynamic>>[],
    },
    {
      'id': 'inventory_tracker_defaults',
      'name': 'Inventory Tracker (With Defaults)',
      'description':
          'Inventory tracker with default Maintaining Qty/Unit and Critical values pre-filled (editable).',
      'iconData': 0xe1d1, // Icons.inventory codepoint
      'colorValue': 0xFF1E3A6E,
      'columns': [
        'Material Name',
        'Comment',
        'Note Type',
        'Note Title',
        'QB Code',
        'Stock',
        'Maintaining Qty',
        'Maintaining Unit',
        'Critical',
        'Total Quantity',
      ],
      'rows': kInventoryTrackerSeedRowsWithDefaults,
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
      final templateId = (template['id'] as String?) ?? '';
      final isInventoryTrackerTemplate = templateId == 'inventory_tracker' ||
          templateId == 'inventory_tracker_empty' ||
          templateId == 'inventory_tracker_defaults';
      final seedThresholdDefaults = templateId == 'inventory_tracker_defaults';

      final cols = List<String>.from(template['columns'] as List);

      Future<SheetModel?> pickInventorySeedSheet(
          List<SheetModel> candidates) async {
        if (candidates.isEmpty) return null;

        final sorted = List<SheetModel>.from(candidates)
          ..sort((a, b) {
            final aDate = a.updatedAt ?? a.createdAt ?? DateTime(2000);
            final bDate = b.updatedAt ?? b.createdAt ?? DateTime(2000);
            return bDate.compareTo(aDate);
          });

        int? selectedId;

        final result = await showDialog<int?>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx2, setLocal) => AlertDialog(
              backgroundColor: _surfaceColor,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text(
                'Base stock on previous tracker',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Choose which Inventory Tracker to copy ending stock from.',
                      style: TextStyle(fontSize: 13, color: _textSecondary),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int?>(
                      initialValue: selectedId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Previous sheet',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: _surfaceAltColor,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Start blank'),
                        ),
                        ...sorted.map(
                          (s) => DropdownMenuItem<int?>(
                            value: s.id,
                            child: Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setLocal(() => selectedId = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx2, null),
                  child:
                      Text('Cancel', style: TextStyle(color: _textSecondary)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: () => Navigator.pop(ctx2, selectedId),
                  child: const Text('Continue'),
                ),
              ],
            ),
          ),
        );

        if (result == null) return null;
        return sorted.where((s) => s.id == result).firstOrNull;
      }

      Future<List<SheetModel>> fetchAllAccessibleSheetsForSeeding() async {
        const limit = 200;
        var page = 1;
        final all = <SheetModel>[];

        while (true) {
          final resp = await ApiService.getSheets(page: page, limit: limit);
          final batch = (resp['sheets'] as List?)
                  ?.map((s) => SheetModel.fromJson(s))
                  .toList() ??
              <SheetModel>[];
          all.addAll(batch);

          final pages = (resp['pagination'] is Map)
              ? (resp['pagination']['pages'] as int? ?? 1)
              : 1;
          if (page >= pages) break;
          page += 1;
        }

        return all;
      }

      String num0(String raw) {
        final cleaned = raw.replaceAll(',', '').trim();
        final n = double.tryParse(cleaned);
        if (n == null || !n.isFinite) return '0';
        return n.toStringAsFixed(0);
      }

      ({String qty, String unit}) parseMaintainingLegacy(String raw) {
        final t = raw.trim();
        if (t.isEmpty) return (qty: '', unit: '');
        final lower = t.toLowerCase();
        if (lower == 'pr' || lower == 'per request' || lower == 'per-request') {
          return (qty: '-', unit: 'PR');
        }
        final cleaned = t.replaceAll(',', '');
        final m =
            RegExp(r'^(-?\d+(?:\.\d+)?)(?:\s+(.+))?$').firstMatch(cleaned);
        if (m == null) return (qty: '', unit: '');
        return (
          qty: (m.group(1) ?? '').trim(),
          unit: (m.group(2) ?? '').trim(),
        );
      }

      List<Map<String, dynamic>>? seededRows;

      // ── Inventory Tracker: inject today's date column automatically ──
      if (isInventoryTrackerTemplate) {
        final now = DateTime.now();
        final yesterdayStr =
            _inventoryDateStr(now.subtract(const Duration(days: 1)));
        final todayStr = _inventoryDateStr(now);
        final totalIdx = cols.indexOf('Total Quantity');
        final insertAt = totalIdx < 0 ? cols.length - 1 : totalIdx;
        cols.insert(insertAt, 'DATE:$yesterdayStr:IN');
        cols.insert(insertAt + 1, 'DATE:$yesterdayStr:OUT');
        cols.insert(insertAt + 2, 'DATE:$todayStr:IN');
        cols.insert(insertAt + 3, 'DATE:$todayStr:OUT');

        // Optional: seed starting Stock from a chosen previous Inventory Tracker.
        // IMPORTANT: pull from all accessible sheets (including those in folders),
        // not just the currently-open folder's list.
        List<SheetModel> candidates = [];
        try {
          final allSheets = await fetchAllAccessibleSheetsForSeeding();
          candidates = allSheets
              .where((s) => _isInventoryTrackerColumns(s.columns))
              .where((s) => s.id != _currentSheet?.id)
              .toList();
        } catch (_) {
          candidates = _sheets
              .where((s) => _isInventoryTrackerColumns(s.columns))
              .where((s) => s.id != _currentSheet?.id)
              .toList();
        }

        final prev = (mounted && candidates.isNotEmpty)
            ? await pickInventorySeedSheet(candidates)
            : null;

        if (prev != null && mounted) {
          try {
            final resp = await ApiService.getSheetData(prev.id);
            final prevFull = SheetModel.fromJson(resp['sheet']);
            final prevRows = prevFull.rows;

            String? findPrevColById(String id) {
              for (final c in prevFull.columns) {
                if (_invColumnId(c) == id) return c;
              }
              return null;
            }

            final prevProductCol = findPrevColById('product_name') ??
                (prevFull.columns.contains('Material Name')
                    ? 'Material Name'
                    : (prevFull.columns.contains('Product Name')
                        ? 'Product Name'
                        : null));
            final prevCodeCol = findPrevColById('code') ??
                (prevFull.columns.contains('QB Code')
                    ? 'QB Code'
                    : (prevFull.columns.contains('QC Code')
                        ? 'QC Code'
                        : null));
            final prevStockCol = findPrevColById('stock') ??
                (prevFull.columns.contains('Stock') ? 'Stock' : null);
            final prevTotalCol = findPrevColById('total_qty') ??
                (prevFull.columns.contains('Total Quantity')
                    ? 'Total Quantity'
                    : null);
            final prevMaintQtyCol = findPrevColById('maintaining_qty') ??
                (prevFull.columns.contains('Maintaining Qty')
                    ? 'Maintaining Qty'
                    : null);
            final prevMaintUnitCol = findPrevColById('maintaining_unit') ??
                (prevFull.columns.contains('Maintaining Unit')
                    ? 'Maintaining Unit'
                    : null);
            final prevCriticalCol = findPrevColById('critical') ??
                (prevFull.columns.contains('Critical') ? 'Critical' : null);
            final prevMaintLegacyCol =
                prevFull.columns.contains('Maintaining') ? 'Maintaining' : null;

            final newHasQB = cols.contains('QB Code');
            final newHasQC = cols.contains('QC Code');
            final newCodeCol =
                newHasQB ? 'QB Code' : (newHasQC ? 'QC Code' : null);
            final newProductCol = cols.contains('Material Name')
                ? 'Material Name'
                : (cols.contains('Product Name') ? 'Product Name' : null);

            seededRows = [];
            for (final r in prevRows) {
              final product =
                  (prevProductCol == null ? '' : (r[prevProductCol] ?? ''))
                      .toString()
                      .trim();
              final code = (prevCodeCol == null
                      ? (r['QB Code'] ?? r['QC Code'] ?? '')
                      : (r[prevCodeCol] ?? ''))
                  .toString()
                  .trim();
              if (product.isEmpty && code.isEmpty) continue;

              String readStr(String? key) {
                if (key == null) return '';
                return (r[key] ?? '').toString();
              }

              // Maintain fields (supports split or legacy).
              var qty = readStr(prevMaintQtyCol).trim();
              var unit = readStr(prevMaintUnitCol).trim();
              if (qty.isEmpty && unit.isEmpty) {
                final legacy = readStr(prevMaintLegacyCol);
                final parsed = parseMaintainingLegacy(legacy);
                qty = parsed.qty;
                unit = parsed.unit;
              }
              final isPr =
                  unit.trim().toUpperCase() == 'PR' || qty.trim() == '-';
              if (isPr) {
                qty = '-';
                unit = 'PR';
              }

              // Carry over ending Total Quantity as new Stock.
              final endingTotal = readStr(prevTotalCol);
              final endingStock = readStr(prevStockCol);
              final stock0 =
                  num0(endingTotal.isNotEmpty ? endingTotal : endingStock);

              final critical0 = readStr(prevCriticalCol).trim();

              final row = <String, dynamic>{};
              if (newProductCol != null) {
                row[newProductCol] = product;
              }
              if (newCodeCol != null) {
                row[newCodeCol] = code;
              }
              if (cols.contains('Stock')) {
                row['Stock'] = stock0;
              }
              if (cols.contains('Maintaining Qty')) {
                row['Maintaining Qty'] = seedThresholdDefaults ? qty : '';
              }
              if (cols.contains('Maintaining Unit')) {
                row['Maintaining Unit'] = seedThresholdDefaults ? unit : '';
              }
              if (cols.contains('Critical')) {
                row['Critical'] = seedThresholdDefaults ? critical0 : '';
              }
              if (cols.contains('Total Quantity')) {
                row['Total Quantity'] = stock0;
              }

              // Ensure date columns are empty for the new month.
              for (final c in cols) {
                if (c.startsWith('DATE:')) {
                  row[c] = '';
                }
              }

              seededRows.add(row);
            }

            // If the previous sheet had no usable rows, fall back to template rows.
            if (seededRows.isEmpty) {
              seededRows = null;
            }
          } catch (_) {
            seededRows = null;
          }
        }
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
      var templateRows =
          List<Map<String, dynamic>>.from(template['rows'] as List);

      // Inventory Tracker: keep the product list, but don't seed quantities.
      // Quantity should come from actual IN/OUT entries (or optional previous-sheet seed).
      if (isInventoryTrackerTemplate && seededRows == null) {
        templateRows = templateRows
            .map((r) => <String, dynamic>{
                  ...r,
                  if (r.containsKey('Stock')) 'Stock': '',
                  if (r.containsKey('Total Quantity')) 'Total Quantity': '',
                })
            .toList(growable: false);
      }
      final sourceRows = seededRows ?? templateRows;
      final initialRowCount = isInventoryTrackerTemplate
          ? (sourceRows.length < 100 ? 100 : sourceRows.length)
          : sourceRows.length.clamp(1, 10000);
      final data = List<Map<String, String>>.generate(initialRowCount, (i) {
        final row = <String, String>{};
        for (final col in cols) {
          // For DATE:* columns not in the template, default to empty string
          row[col] = i < sourceRows.length
              ? (sourceRows[i][col]?.toString() ?? '')
              : '';
        }
        return row;
      });

      // Pre-save the sample rows so they appear immediately
      if (sourceRows.isNotEmpty) {
        try {
          await ApiService.updateSheet(
            sheet.id,
            name,
            cols,
            data
                .take(sourceRows.length)
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
        _clearGridMetaState();

        _inventoryRowCacheDirty = true;
        _inventoryRowPrefixDirty = true;
        _inventoryColumnCacheDirty = true;

        if (isInventoryTrackerTemplate) {
          _inventorySortMode = _InventorySortMode.normal;
        }

        _rowLabels = List.generate(initialRowCount, (i) => _defaultRowLabel(i));
        _selectedRow = null;
        _selectedCol = null;
        _selectionEndRow = null;
        _selectionEndCol = null;
        _editingRow = null;
        _editingCol = null;
        _isLoading = false;
      });
      _clearHistory();

      // Join the sheet room immediately so template-created sheets have
      // real-time typing/cell updates/cell focus without re-opening.
      unawaited(_refreshSheetStatus());
      if (_currentSheet != null) {
        _startSheetCollaboration(_currentSheet!.id);
      }

      // Inventory dashboard sheet filter is driven by DataProvider.
      if (mounted) {
        context.read<DataProvider>().setCurrentSheet(
              sheetId: sheet.id,
              sheetName: sheet.name,
            );
        context.read<DataProvider>().loadInventorySheets();
      }

      // Recalc totals so Stock/Total Quantity reflect IN/OUT values.
      if (isInventoryTrackerTemplate) {
        _recalcInventoryTotals();
        await _saveSheet();
      }

      if (mounted) {
        AppModal.showText(
          context,
          title: 'Success',
          message: 'Sheet "$name" created from ${template['name']} template',
        );
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to create from template: $e',
        );
      }
    }
  }

  // ════════════════════════════════════════════
  //  Folder Management
  // ════════════════════════════════════════════

  // ignore: unused_element
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
                color: Colors.amber.withValues(alpha: 0.1),
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
                  color: Colors.amber.withValues(alpha: _isDark ? 0.18 : 0.12),
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
                  initialValue: selectedParentId,
                  decoration: InputDecoration(
                    labelText: 'Location',
                    labelStyle: TextStyle(color: _textSecondary),
                    floatingLabelStyle: const TextStyle(color: _kBlue),
                    prefixIcon:
                        Icon(Icons.folder_open_outlined, color: _textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kBlue, width: 1.5),
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
                  textAlignVertical: TextAlignVertical.center,
                  style: TextStyle(color: _textPrimary),
                  cursorColor: _kBlue,
                  decoration: InputDecoration(
                    labelText: 'Folder Name',
                    hintText: 'Enter folder name',
                    labelStyle: TextStyle(color: _textSecondary),
                    floatingLabelStyle: const TextStyle(color: _kBlue),
                    hintStyle: TextStyle(color: _textSecondary),
                    prefixIcon:
                        Icon(Icons.folder_outlined, color: _textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _kBlue, width: 1.5),
                    ),
                    filled: true,
                    fillColor: _surfaceAltColor,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
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
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Folder name must be at least 2 characters',
        );
        return;
      }

      if (trimmedName.length > 50) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Folder name must be less than 50 characters',
        );
        return;
      }

      // Check for invalid characters
      final invalidChars = RegExp(r'[<>:"/\\|?*]');
      if (invalidChars.hasMatch(trimmedName)) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Folder name contains invalid characters',
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
        AppModal.showText(
          context,
          title: success ? 'Success' : 'Error',
          message: success
              ? 'Folder "$trimmedName" created successfully'
              : 'Failed to create folder',
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
        AppModal.showText(
          context,
          title: 'Success',
          message: targetFolderId == null
              ? '"${sheet.name}" moved to root'
              : '"${sheet.name}" moved to folder',
        );
        await _loadSheets();
        await _refreshAllSheetsExplorerCache();
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to move sheet: $e',
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

    if (_isInventoryTrackerSheet()) {
      _inventoryStockCountsDirty = true;
    }

    _scheduleAutoSave();
  }

  void _scheduleAutoSave() {
    // Debounced auto-save: persist to DB a moment after the last change.
    // IMPORTANT: never auto-save while the user is actively editing a cell;
    // that can persist partial text and make product names appear "cut".
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted || !_hasUnsavedChanges) return;

      // Defer until the user commits/cancels the current cell edit.
      if (_editingRow != null) {
        _scheduleAutoSave();
        return;
      }

      _saveSheet();
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
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Cannot save: $_lockedByUser is currently editing this sheet',
      );
      return;
    }

    // Use _saveStatus for the indicator; do NOT touch _isLoading so the
    // grid is never replaced by a spinner during a background save.
    setState(() => _saveStatus = 'saving');

    try {
      // Preserve row numbers: save all rows up to the last non-empty row,
      // including any empty rows in-between.
      int lastNonEmpty = -1;
      for (int i = _data.length - 1; i >= 0; i--) {
        if (_data[i].values.any((v) => v.isNotEmpty)) {
          lastNonEmpty = i;
          break;
        }
      }
      final rowsToSave = lastNonEmpty >= 0
          ? _data.take(lastNonEmpty + 1).toList()
          : <Map<String, String>>[];

      await ApiService.updateSheet(
        _currentSheet!.id,
        _currentSheet!.name,
        _columns,
        rowsToSave,
        gridMeta: _buildGridMetaForSave(),
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
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to save: $e',
        );
      }
    }
  }

  Future<String?> _showNameDialog(String title, String hint,
      {String? initialValue}) async {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
        final fieldBg =
            isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);
        final border =
            isDark ? const Color(0xFF334155) : _SheetScreenState._kBorder;
        final titleColor =
            isDark ? const Color(0xFFF1F5F9) : _SheetScreenState._kNavy;
        final bodyColor =
            isDark ? const Color(0xFF94A3B8) : _SheetScreenState._kGray;

        OutlineInputBorder outline(Color color) => OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: color, width: 1),
            );

        return AlertDialog(
          backgroundColor: dialogBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: border, width: 1),
          ),
          title: Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: titleColor,
              letterSpacing: 0.2,
            ),
          ),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: hint,
              labelStyle: TextStyle(color: bodyColor),
              filled: true,
              fillColor: fieldBg,
              enabledBorder: outline(border),
              focusedBorder:
                  outline(_SheetScreenState._kBlue.withValues(alpha: 0.85)),
              border: outline(border),
            ),
            style: TextStyle(color: titleColor),
            autofocus: true,
            onSubmitted: (value) => Navigator.pop(context, value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              style: TextButton.styleFrom(foregroundColor: bodyColor),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: _SheetScreenState._kBlue,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _renameColumn(int colIndex) async {
    if (!_canEditSheet()) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'You do not have permission to rename columns.',
      );
      return;
    }

    final oldStoredKey = _columns[colIndex];
    if (_isInventoryTrackerSheet() && oldStoredKey.startsWith('DATE:')) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Date columns cannot be renamed in Inventory Tracker.',
      );
      return;
    }

    final currentName = _displayColumnName(oldStoredKey);
    final newName = await _showNameDialog(
      'Rename Column',
      'Enter new column name',
      initialValue: currentName,
    );

    if (!mounted) return;

    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == currentName) return;

    final normalized = trimmed.toLowerCase();
    final bool dupDisplay = _columns.asMap().entries.any((e) {
      if (e.key == colIndex) return false;
      return _displayColumnName(e.value).trim().toLowerCase() == normalized;
    });

    if (dupDisplay) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Column name already exists',
      );
      return;
    }

    // Inventory Tracker: preserve semantic ids for renamed headers.
    String? invId = _invColumnId(oldStoredKey);
    if (invId == null && _isInventoryTrackerSheet()) {
      switch (oldStoredKey) {
        case 'Material Name':
        case 'Product Name':
          invId = 'product_name';
          break;
        case 'QB Code':
        case 'QC Code':
          invId = 'code';
          break;
        case 'Stock':
          invId = 'stock';
          break;
        case 'Maintaining Qty':
          invId = 'maintaining_qty';
          break;
        case 'Maintaining Unit':
          invId = 'maintaining_unit';
          break;
        case 'Critical':
          invId = 'critical';
          break;
        case 'Total Quantity':
          invId = 'total_qty';
          break;
        case _kInventoryCommentCol:
          invId = 'comment';
          break;
        case _kInventoryNoteTypeCol:
          invId = 'note_type';
          break;
        case _kInventoryNoteTitleCol:
          invId = 'note_title';
          break;
      }
    }

    final newStoredKey =
        invId != null ? _invEncodeColKey(invId, trimmed) : trimmed;

    _pushUndoSnapshot();
    setState(() {
      _columns[colIndex] = newStoredKey;
      for (final row in _data) {
        if (row.containsKey(oldStoredKey)) {
          row[newStoredKey] = row[oldStoredKey] ?? '';
          row.remove(oldStoredKey);
        }
      }
      _updateFormulaBar();
    });

    _markDirty();

    AppModal.showText(
      context,
      title: 'Success',
      message: 'Column renamed to "$trimmed"',
    );
  }

  Future<void> _renameRow(int rowIndex) async {
    final currentLabel = _rowLabels[rowIndex];
    final newLabel = await _showNameDialog(
      'Rename Row',
      'Enter new row label',
      initialValue: currentLabel,
    );

    if (!mounted) return;

    if (newLabel == null || newLabel.isEmpty || newLabel == currentLabel) {
      return;
    }

    setState(() {
      _rowLabels[rowIndex] = newLabel;
    });

    AppModal.showText(
      context,
      title: 'Success',
      message: 'Row renamed to "$newLabel"',
    );
  }

  Future<void> _renameSheet(SheetModel sheet) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';

    // Check permissions - only admin and editor can rename
    if (userRole != 'admin' && userRole != 'editor') {
      AppModal.showText(
        context,
        title: 'Error',
        message: 'You do not have permission to rename sheets',
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
        AppModal.showText(
          context,
          title: 'Success',
          message: 'Sheet renamed to "$newName"',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to rename sheet: $e',
        );
      }
    }
  }

  Future<void> _confirmDeleteSheet(SheetModel sheet) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final userRole = authProvider.user?.role ?? '';

    // Check permissions - only admin can delete
    if (userRole != 'admin') {
      AppModal.showText(
        context,
        title: 'Error',
        message: 'You do not have permission to delete sheets',
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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).brightness == Brightness.dark
                  ? const Color(0xFFD1D5DB)
                  : null,
            ),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete Selected Sheets'),
        content: Text(
            'Permanently delete $count sheet${count > 1 ? 's' : ''}? This cannot be undone.'),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    Theme.of(dialogContext).brightness == Brightness.dark
                        ? const Color(0xFFD1D5DB)
                        : null,
              ),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move to Folder'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Root (no folder)'),
                onTap: () => Navigator.pop(dialogContext, -1),
              ),
              const Divider(height: 1),
              ...allFolders.map((f) => ListTile(
                    leading: const Icon(Icons.folder, color: Colors.amber),
                    title: Text(f['name'] ?? ''),
                    onTap: () => Navigator.pop(dialogContext, f['id'] as int),
                  )),
            ],
          ),
        ),
        actions: [
          TextButton(
              style: TextButton.styleFrom(
                foregroundColor:
                    Theme.of(dialogContext).brightness == Brightness.dark
                        ? const Color(0xFFD1D5DB)
                        : null,
              ),
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel')),
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
    await _refreshAllSheetsExplorerCache();
  }

  Future<void> _deleteSheet(int sheetId) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      await ApiService.deleteSheet(sheetId);
      if (!mounted) return;

      // If the deleted sheet was the current sheet, clear it
      if (_currentSheet?.id == sheetId) {
        SocketService.instance.leaveSheet(sheetId);
        _stopLiveTyping();
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
          _rowLabels = List.generate(100, (index) => _defaultRowLabel(index));
          // Clear selections
          _selectedRow = null;
          _selectedCol = null;
          _selectionEndRow = null;
          _selectionEndCol = null;
          _editingRow = null;
          _editingCol = null;
          _presenceUsers = [];
          _cellPresenceUserIds.clear();
          _presenceInfoMap.clear();
          _activeSheetUsers = [];
        });
        if (mounted) {
          context.read<DataProvider>().clearCurrentSheet();
        }
      }

      // Reload the sheets list
      await _loadSheets();

      if (mounted) {
        AppModal.showText(
          context,
          title: 'Success',
          message: 'Sheet deleted successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to delete sheet: $e',
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
    _invalidateInventoryColumnCache();
    _markDirty();
  }

  void _addRow() {
    if (widget.readOnly) return;
    if (_editingRow != null) {
      _saveEdit();
    }

    // Inventory Tracker: if a search filter is active, a new blank row would be
    // filtered out and the auto-scroll would appear to do nothing.
    if (_isInventoryTrackerSheet() && _inventorySearchQuery.isNotEmpty) {
      setState(() {
        _inventorySearchQuery = '';
        _inventorySearchController.clear();
      });
      _invalidateInventoryRowCache();
    }

    final int baseRow = (_selectedRow == null)
        ? (_data.isEmpty ? -1 : _data.length - 1)
        : _selectedRow!.clamp(0, _data.isEmpty ? 0 : _data.length - 1);
    final int insertIndex = (baseRow + 1).clamp(0, _data.length);

    _pushUndoSnapshot();
    setState(() {
      final row = <String, String>{};
      for (var col in _columns) {
        row[col] = '';
      }
      _data.insert(insertIndex, row);

      // Insert a new label; keep custom labels but renumber purely-numeric ones.
      _rowLabels.insert(insertIndex, _defaultRowLabel(insertIndex));
      for (int i = 0; i < _rowLabels.length; i++) {
        if (RegExp(r'^\\d+$').hasMatch(_rowLabels[i])) {
          _rowLabels[i] = _defaultRowLabel(i);
        }
      }

      _selectedRow = insertIndex;
      _selectionEndRow = insertIndex;
      _selectedCol = (_selectedCol ?? 0)
          .clamp(0, _columns.isEmpty ? 0 : _columns.length - 1);
      _selectionEndCol = _selectedCol;
      _editingRow = null;
      _editingCol = null;
      _updateFormulaBar();
    });

    _invalidateInventoryRowCache();

    _markDirty();
    _scrollToRowAfterFrame(insertIndex);
  }

  void _scrollToRowAfterFrame(int rowIndex) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_verticalScrollController.hasClients) return;

      final double targetOffset = _scrollOffsetForRowInCurrentView(rowIndex);
      final double max = _verticalScrollController.position.maxScrollExtent;
      final double clamped = targetOffset.clamp(0.0, max);

      _verticalScrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  double _scrollOffsetForRowInCurrentView(int rowIndex) {
    // Inventory grid has its own filtered/sorted order and includes header rows
    // inside the scrollable content.
    if (_isInventoryTrackerSheet()) {
      _ensureInventoryRowCache();
      final prefix = _inventoryCachedRowPrefixHeights;
      final entriesLen = _inventoryCachedEntries.length;
      if (prefix.length != entriesLen + 1) {
        return _verticalScrollController.hasClients
            ? _verticalScrollController.offset
            : 0.0;
      }

      final displayRow = _inventoryDisplayRowNumberByRowIndex[rowIndex];
      final visibleIndex = displayRow == null ? -1 : (displayRow - 3);
      if (visibleIndex < 0) {
        return _verticalScrollController.hasClients
            ? _verticalScrollController.offset
            : 0.0;
      }

      final double accY = (_invHeaderH1 + _invHeaderH2) + prefix[visibleIndex];

      // Scroll coordinates are in the zoom-scaled space.
      return (accY * _zoomLevel);
    }

    // Regular spreadsheet: vertical scrollable area is data rows only.
    double accY = 0;
    for (int r = 0; r < _data.length; r++) {
      if (_isRowHidden(r)) continue;
      if (r == rowIndex) break;
      accY += _getRowHeight(r);
    }
    return (accY * _zoomLevel);
  }

  void _deleteColumn() {
    if (_selectedCol == null) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Please select a column to delete',
      );
      return;
    }

    if (_columns.length <= 1) {
      AppModal.showText(
        context,
        title: 'Error',
        message: 'Cannot delete the last column',
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
    _invalidateInventoryColumnCache();
    _markDirty();

    AppModal.showText(
      context,
      title: 'Success',
      message: 'Column $colToDelete deleted',
    );
  }

  void _deleteRow() {
    if (_selectedRow == null) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Please select a row to delete',
      );
      return;
    }

    // Don't allow deleting if only a few rows left
    if (_data.length <= 10) {
      AppModal.showText(
        context,
        title: 'Error',
        message: 'Cannot delete row - minimum 10 rows required',
      );
      return;
    }

    final rowLabel = _rowLabels[_selectedRow!];

    _pushUndoSnapshot();
    setState(() {
      _data.removeAt(_selectedRow!);
      _rowLabels.removeAt(_selectedRow!);
      _selectedRow = null;
      _selectionEndRow = null;
    });

    _invalidateInventoryRowCache();
    _markDirty();

    AppModal.showText(
      context,
      title: 'Success',
      message: 'Row $rowLabel deleted',
    );
  }

  Future<void> _exportSheet(String format) async {
    if (_currentSheet == null) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'No sheet selected to export',
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
            AppModal.showText(
              context,
              title: 'Success',
              message: 'Sheet exported successfully to $outputPath',
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

            AppModal.showText(
              context,
              title: 'Error',
              message: errorMessage,
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to export: $e',
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
          AppModal.showText(
            context,
            title: 'Error',
            message: 'Could not read file',
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
        AppModal.show(
          context,
          title: 'Imported',
          content: Text(
            'Imported "${sheet.name}" — $rowCount rows, $colCount columns',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _loadSheetData(sheet.id);
              },
              child: const Text('Open'),
            ),
          ],
        );
        // Refresh the sheet list so the new sheet appears
        _loadSheets();
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Import failed: $e',
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
      AppModal.showText(
        context,
        title: 'Notice',
        message: '$_lockedByUser is currently editing this sheet',
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
      AppModal.showText(
        context,
        title: 'Notice',
        message: '$name is currently editing this cell',
      );
      return;
    }

    setState(() {
      _editingRow = row;
      _editingCol = col;
      _lastInvalidInventoryDialogKey = null;
      _originalCellValue = _data[row][_columns[col]] ?? '';
      _suppressLiveTyping = true;
      _editController.text = _originalCellValue;
      _suppressLiveTyping = false;

      // Reset real-time trackers for this edit session.
      _liveTypingLastSent = '';
      _liveCommitLastSent = _editController.text;

      // Inventory Tracker: if Stock is blank but Total Quantity is present,
      // prefill the editor with Total Quantity so the user can edit/save it.
      if (_isInventoryTrackerSheet()) {
        final stockKey = _inventoryStockKey();
        final totalKey = _inventoryTotalQtyKey();
        final colKey = _columns[col];
        if (stockKey != null &&
            totalKey != null &&
            colKey == stockKey &&
            _originalCellValue.trim().isEmpty) {
          final derived = (_data[row][totalKey] ?? '').toString().trim();
          if (derived.isNotEmpty) {
            _suppressLiveTyping = true;
            _editController.text = derived;
            _suppressLiveTyping = false;

            _liveCommitLastSent = _editController.text;
          }
        }
      }
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
      _stopLiveTyping();
      _lastInvalidInventoryDialogKey = null;
      final savedRow = _editingRow!;
      final savedCol = _editingCol!;
      final cellRef = _getCellReference(savedRow, savedCol);
      final colName = _columns[savedCol];
      const maintainingQtyCol = 'Maintaining Qty';
      const maintainingUnitCol = 'Maintaining Unit';
      final inventoryStockKey = _inventoryStockKey();
      final inventoryTotalKey = _inventoryTotalQtyKey();

      bool isPerRequestUnit(String v) {
        final lower = v.trim().toLowerCase();
        return lower == 'pr' ||
            lower == 'per request' ||
            lower == 'per-request';
      }

      String normalizeMaintainingUnit(String v) {
        if (isPerRequestUnit(v)) return 'PR';
        return v.trim();
      }

      String normalizeMaintainingQty(String v) {
        final t = v.trim();
        return t == '-' ? '-' : t;
      }

      final rawNewValue = _editController.text;
      if (_handleInvalidInventoryOutSubmission(
        rowIndex: savedRow,
        colName: colName,
        proposedValueRaw: rawNewValue,
        previousValue: _originalCellValue,
        cellRef: cellRef,
      )) {
        return;
      }

      final updates = <String, String>{};
      updates[colName] = rawNewValue;

      // Inventory Tracker: Stock is the editable baseline input.
      // Keep Total Quantity immediately in sync with Stock edits (then recalc
      // will apply IN/OUT math if any date entries exist).
      if (_isInventoryTrackerSheet() &&
          inventoryStockKey != null &&
          inventoryTotalKey != null &&
          colName == inventoryStockKey &&
          inventoryTotalKey != inventoryStockKey) {
        updates[inventoryTotalKey] = rawNewValue;
      }

      // Inventory Tracker: enforce PR rule.
      // If unit is PR (per request) → qty must be '-'.
      // If qty is '-' → unit must be 'PR'.
      if (_isInventoryTrackerSheet() &&
          _columns.contains(maintainingQtyCol) &&
          _columns.contains(maintainingUnitCol)) {
        if (colName == maintainingUnitCol) {
          final unit = normalizeMaintainingUnit(rawNewValue);
          updates[maintainingUnitCol] = unit;
          if (unit == 'PR') {
            updates[maintainingQtyCol] = '-';
          }
        } else if (colName == maintainingQtyCol) {
          final qty = normalizeMaintainingQty(rawNewValue);
          updates[maintainingQtyCol] = qty;
          if (qty == '-') {
            updates[maintainingUnitCol] = 'PR';
          }
        }
      }

      // Apply normalization even when only one column exists (back-compat).
      if (_isInventoryTrackerSheet()) {
        if (colName == maintainingUnitCol) {
          updates[colName] = normalizeMaintainingUnit(rawNewValue);
        } else if (colName == maintainingQtyCol) {
          updates[colName] = normalizeMaintainingQty(rawNewValue);
        }
      }

      bool changedAny = false;
      for (final entry in updates.entries) {
        final k = entry.key;
        final v = entry.value;
        final prev =
            (k == colName) ? _originalCellValue : (_data[savedRow][k] ?? '');
        if (v != prev) {
          changedAny = true;
          break;
        }
      }

      final prevValues = <String, String>{
        for (final k in updates.keys)
          k: (k == colName) ? _originalCellValue : (_data[savedRow][k] ?? ''),
      };

      if (changedAny) {
        _pushUndoSnapshot();
      }
      setState(() {
        for (final entry in updates.entries) {
          _data[savedRow][entry.key] = entry.value;
        }
        _editingRow = null;
        _editingCol = null;
        _updateFormulaBar();
        // Consume single-use temp access for this cell
        _grantedCells.remove(cellRef);
      });

      // If the Inventory view is currently filtered/sorted, row membership/order
      // can change when values change (e.g. search hits, A–Z sort). Rebuild the
      // cached entry list lazily.
      if (_isInventoryTrackerSheet() &&
          (_inventorySearchQuery.trim().isNotEmpty ||
              _inventorySortMode != _InventorySortMode.normal)) {
        _invalidateInventoryRowCache();
      }
      if (_currentSheet != null) {
        SocketService.instance.cellBlur(_currentSheet!.id, cellRef);
        // ── Real-time broadcast: push the new value to all other users immediately ──
        if (changedAny) {
          for (final entry in updates.entries) {
            final k = entry.key;
            final v = entry.value;
            final prev = prevValues[k] ?? '';
            if (v != prev) {
              SocketService.instance.cellUpdate(
                _currentSheet!.id,
                savedRow,
                k,
                v,
              );
            }
          }
        }
      }
      if (_isInventoryTrackerSheet() &&
          _isInventoryTotalsInputColumn(colName)) {
        _recalcInventoryTotalsForRow(savedRow);
      }

      // Explicit: editing Stock should always recompute Total Quantity.
      if (_isInventoryTrackerSheet() &&
          inventoryStockKey != null &&
          colName == inventoryStockKey) {
        _recalcInventoryTotalsForRow(savedRow);
      }
      if (changedAny) _markDirty();
    }
  }

  void _cancelEdit() {
    final row = _editingRow;
    final col = _editingCol;
    final sheetId = _currentSheet?.id;
    final cellRef =
        (row != null && col != null) ? _getCellReference(row, col) : null;
    final colName =
        (row != null && col != null && col >= 0 && col < _columns.length)
            ? _columns[col]
            : null;
    final original = _originalCellValue;

    _stopLiveTyping();
    _lastInvalidInventoryDialogKey = null;
    setState(() {
      _editingRow = null;
      _editingCol = null;
    });
    if (sheetId != null && row != null && colName != null) {
      SocketService.instance.cellCancel(sheetId, row, colName, original);

      // Ensure DB matches the canceled value (in case auto-commit already
      // persisted partial typing).
      SocketService.instance.cellUpdate(sheetId, row, colName, original);
    }
    if (cellRef != null && sheetId != null) {
      SocketService.instance.cellBlur(sheetId, cellRef);
    }
  }

  void _stopLiveTyping() {
    _liveTypingDebounce?.cancel();
    _liveTypingDebounce = null;
    _liveTypingLastSent = '';

    _liveCommitDebounce?.cancel();
    _liveCommitDebounce = null;
    _liveCommitLastSent = '';
  }

  void _scheduleInventoryTotalsRecalcForRow(int rowIndex) {
    if (rowIndex < 0) return;

    _inventoryTotalsRecalcTimers[rowIndex]?.cancel();
    _inventoryTotalsRecalcTimers[rowIndex] =
        Timer(const Duration(milliseconds: 120), () {
      _inventoryTotalsRecalcTimers.remove(rowIndex);
      if (!mounted) return;
      if (!_isInventoryTrackerSheet()) return;
      if (rowIndex >= _data.length) return;
      _recalcInventoryTotalsForRow(rowIndex);
    });
  }

  void _queueRemoteTypingUpdate({
    required int sheetId,
    required int rowIndex,
    required String colName,
    required String value,
  }) {
    final key = '$rowIndex|$colName';
    _pendingRemoteTypingSheetId = sheetId;
    _pendingRemoteTypingCells[key] = value;

    _pendingRemoteTypingFlush?.cancel();
    _pendingRemoteTypingFlush = Timer(const Duration(milliseconds: 50), () {
      if (!mounted) return;
      if (_currentSheet?.id != _pendingRemoteTypingSheetId) {
        _pendingRemoteTypingCells.clear();
        return;
      }

      bool shouldUpdateFormulaBar = false;
      bool addedRowOrCol = false;
      bool shouldInvalidateRows = _isInventoryTrackerSheet() &&
          (_inventorySearchQuery.trim().isNotEmpty ||
              _inventorySortMode != _InventorySortMode.normal);
      final updates = Map<String, String>.from(_pendingRemoteTypingCells);
      _pendingRemoteTypingCells.clear();

      setState(() {
        for (final entry in updates.entries) {
          final parts = entry.key.split('|');
          if (parts.length != 2) continue;
          final r = int.tryParse(parts[0]);
          final cName = parts[1];
          if (r == null || cName.isEmpty) continue;

          while (_data.length <= r) {
            final emptyRow = <String, String>{};
            for (final c in _columns) {
              emptyRow[c] = '';
            }
            _data.add(emptyRow);
            _rowLabels.add(_defaultRowLabel(_data.length - 1));
            addedRowOrCol = true;
          }

          if (!_columns.contains(cName)) {
            _columns.add(cName);
            for (final row in _data) {
              row.putIfAbsent(cName, () => '');
            }
            addedRowOrCol = true;
          }

          _data[r][cName] = entry.value;

          if (_selectedRow == r &&
              _selectedCol != null &&
              _selectedCol! >= 0 &&
              _selectedCol! < _columns.length &&
              _columns[_selectedCol!] == cName) {
            shouldUpdateFormulaBar = true;
          }

          if (_isInventoryTotalsInputColumn(cName)) {
            _scheduleInventoryTotalsRecalcForRow(r);
          }
        }

        if (_isInventoryTrackerSheet()) {
          _inventoryStockCountsDirty = true;
        }
      });

      if (addedRowOrCol) {
        _invalidateInventoryColumnCache();
        _invalidateInventoryRowCache();
      } else if (shouldInvalidateRows) {
        _invalidateInventoryRowCache();
      }

      if (shouldUpdateFormulaBar) _updateFormulaBar();
    });
  }

  void _onLocalEditControllerChanged() {
    if (_suppressLiveTyping) return;
    final sheetId = _currentSheet?.id;
    final row = _editingRow;
    final col = _editingCol;
    if (sheetId == null || row == null || col == null) return;
    if (col < 0 || col >= _columns.length) return;

    final colName = _columns[col];
    final value = _editController.text;

    final bool isInvDateQty = _isInventoryTrackerSheet() &&
        colName.startsWith('DATE:') &&
        (colName.endsWith(':OUT') || colName.endsWith(':IN'));
    if (isInvDateQty) {
      final prevValue =
          (row >= 0 && row < _data.length) ? (_data[row][colName] ?? '') : '';
      final isInvalid = _isInventoryDateQtyEditInvalid(
        rowIndex: row,
        colName: colName,
        proposedValueRaw: value,
      );
      if (isInvalid) {
        _liveTypingDebounce?.cancel();
        _liveTypingDebounce = null;
        _liveCommitDebounce?.cancel();
        _liveCommitDebounce = null;

        // Revert the editor back to the last known valid value (or 0).
        final fallback = prevValue.trim().isEmpty ? '0' : prevValue;
        _suppressLiveTyping = true;
        _editController.text = fallback;
        _editController.selection =
            TextSelection.collapsed(offset: fallback.length);
        _suppressLiveTyping = false;

        // Keep totals consistent with the reverted value.
        if (row >= 0 && row < _data.length) {
          _data[row][colName] = fallback;
          _scheduleInventoryTotalsRecalcForRow(row);
        }

        _maybeShowInvalidInventoryAmountDialog(rowIndex: row, colName: colName);
        return;
      }
    }

    // Keep local sheet data in sync while editing so autosave/other logic
    // doesn't lag behind the editor.
    //
    // Important: avoid setState() on each keystroke. The TextField already
    // renders the typed text, and rebuilding the full grid is especially
    // expensive for Inventory Tracker (sorting + totals scans).
    if (row >= 0 && row < _data.length) {
      _data[row][colName] = value;
    }
    final bool shouldUpdateFormulaBar = _selectedRow == row &&
        _selectedCol != null &&
        _selectedCol! >= 0 &&
        _selectedCol! < _columns.length &&
        _columns[_selectedCol!] == colName;
    if (shouldUpdateFormulaBar && !_formulaBarFocusNode.hasFocus) {
      _updateFormulaBar();
    }

    // Inventory Tracker: keep totals responsive while typing in input columns.
    if (_isInventoryTrackerSheet() && _isInventoryTotalsInputColumn(colName)) {
      _scheduleInventoryTotalsRecalcForRow(row);
    }

    // Skip duplicate sends.
    if (value == _liveTypingLastSent) return;
    _liveTypingLastSent = value;

    // Throttle: coalesce rapid keystrokes into ~1 update / 60ms.
    _liveTypingDebounce?.cancel();
    _liveTypingDebounce = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      if (_currentSheet?.id != sheetId) return;
      if (_editingRow != row || _editingCol != col) return;
      SocketService.instance.cellTyping(sheetId, row, colName, value);
    });

    // Auto-commit (persist) after the user pauses typing.
    // This prevents conflicts where another user reloads and gets old DB data.
    if (value != _liveCommitLastSent) {
      _liveCommitDebounce?.cancel();
      _liveCommitDebounce = Timer(const Duration(milliseconds: 650), () {
        if (!mounted) return;
        if (_currentSheet?.id != sheetId) return;
        if (_editingRow != row || _editingCol != col) return;

        // Inventory Tracker: never auto-commit invalid IN/OUT values.
        if (_isInventoryDateQtyEditInvalid(
          rowIndex: row,
          colName: colName,
          proposedValueRaw: value,
        )) {
          return;
        }

        // Avoid resending if already committed.
        if (value == _liveCommitLastSent) return;
        _liveCommitLastSent = value;

        SocketService.instance.cellUpdate(sheetId, row, colName, value);
        _markDirty();
      });
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
      columnWidths: Map<int, double>.from(_columnWidths),
      rowHeights: Map<int, double>.from(_rowHeights),
      hiddenColumns: Set<int>.from(_hiddenColumns),
      hiddenRows: Set<int>.from(_hiddenRows),
      collapsedRows: Set<int>.from(_collapsedRows),
      cellFormats: _cellFormats.map((k, v) => MapEntry(k, Set<String>.from(v))),
      cellFontSizes: Map<String, double>.from(_cellFontSizes),
      cellAlignments: Map<String, TextAlign>.from(_cellAlignments),
      cellTextColors: Map<String, Color>.from(_cellTextColors),
      cellBackgroundColors: Map<String, Color>.from(_cellBackgroundColors),
      cellBorders:
          _cellBorders.map((k, v) => MapEntry(k, Map<String, bool>.from(v))),
      mergedCellRanges: Set<String>.from(_mergedCellRanges),
      currentFontSize: _currentFontSize,
      currentTextColor: _currentTextColor,
      currentBackgroundColor: _currentBackgroundColor,
      invHeaderH1: _invHeaderH1,
      invHeaderH2: _invHeaderH2,
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
      _columnWidths.clear();
      _columnWidths.addAll(snapshot.columnWidths);
      _rowHeights.clear();
      _rowHeights.addAll(snapshot.rowHeights);
      _hiddenColumns.clear();
      _hiddenColumns.addAll(snapshot.hiddenColumns);
      _hiddenRows.clear();
      _hiddenRows.addAll(snapshot.hiddenRows);
      _collapsedRows.clear();
      _collapsedRows.addAll(snapshot.collapsedRows);

      _cellFormats
        ..clear()
        ..addAll(snapshot.cellFormats
            .map((k, v) => MapEntry(k, Set<String>.from(v))));
      _cellFontSizes
        ..clear()
        ..addAll(snapshot.cellFontSizes);
      _cellAlignments
        ..clear()
        ..addAll(snapshot.cellAlignments);
      _cellTextColors
        ..clear()
        ..addAll(snapshot.cellTextColors);
      _cellBackgroundColors
        ..clear()
        ..addAll(snapshot.cellBackgroundColors);
      _cellBorders
        ..clear()
        ..addAll(snapshot.cellBorders
            .map((k, v) => MapEntry(k, Map<String, bool>.from(v))));
      _mergedCellRanges
        ..clear()
        ..addAll(snapshot.mergedCellRanges);
      _currentFontSize = snapshot.currentFontSize;
      _currentTextColor = snapshot.currentTextColor;
      _currentBackgroundColor = snapshot.currentBackgroundColor;

      _invHeaderH1 = snapshot.invHeaderH1;
      _invHeaderH2 = snapshot.invHeaderH2;
      _editingRow = null;
      _editingCol = null;
      _updateFormulaBar();
    });

    _inventoryRowCacheDirty = true;
    _inventoryRowPrefixDirty = true;
    _inventoryColumnCacheDirty = true;
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

    final h = _rowHeights[rowIndex] ?? _cellHeight;
    if (!h.isFinite) return _cellHeight;
    // Guard against corrupted/legacy values that could break layout.
    return h.clamp(_minRowHeight, _maxRowHeight).toDouble();
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
    _invalidateInventoryRowCache(prefixOnly: true);
  }

  // ignore: unused_element
  void _expandAllRows() {
    setState(() {
      _collapsedRows.clear();
    });
    _invalidateInventoryRowCache(prefixOnly: true);
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
    _invalidateInventoryRowCache(prefixOnly: true);
  }

  // =============== Hide/Unhide Helper Methods ===============

  /// Check if a column is hidden
  bool _isColumnHidden(int colIndex) {
    return _hiddenColumns.contains(colIndex);
  }

  /// Check if a row is hidden
  bool _isRowHidden(int rowIndex) {
    return _hiddenRows.contains(rowIndex);
  }

  /// Get the actual (visible) column width - 0 if hidden
  double _getVisibleColumnWidth(int colIndex) {
    if (_isColumnHidden(colIndex)) return 0.0;
    return _getColumnWidth(colIndex);
  }

  /// Get the actual (visible) row height - 0 if hidden
  double _getVisibleRowHeight(int rowIndex) {
    if (_isRowHidden(rowIndex)) return 0.0;
    return _getRowHeight(rowIndex);
  }

  /// Hide selected columns
  // ignore: unused_element
  void _hideSelectedColumns() {
    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
        _hiddenColumns.add(c);
      }
      _clearSelection();
    });
    _invalidateInventoryColumnCache();
    _markDirty();
  }

  /// Hide selected rows
  // ignore: unused_element
  void _hideSelectedRows() {
    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        _hiddenRows.add(r);
      }
      _clearSelection();
    });
    _invalidateInventoryRowCache();
    _markDirty();
  }

  /// Unhide column at index
  // ignore: unused_element
  void _unhideColumn(int colIndex) {
    _pushUndoSnapshot();
    setState(() {
      _hiddenColumns.remove(colIndex);
    });
    _invalidateInventoryColumnCache();
    _markDirty();
  }

  /// Unhide row at index
  // ignore: unused_element
  void _unhideRow(int rowIndex) {
    _pushUndoSnapshot();
    setState(() {
      _hiddenRows.remove(rowIndex);
    });
    _invalidateInventoryRowCache();
    _markDirty();
  }

  /// Unhide all columns
  void _unhideAllColumns() {
    if (_hiddenColumns.isEmpty) return;
    _pushUndoSnapshot();
    setState(() {
      _hiddenColumns.clear();
    });
    _invalidateInventoryColumnCache();
    _markDirty();
  }

  /// Unhide all rows
  void _unhideAllRows() {
    if (_hiddenRows.isEmpty) return;
    _pushUndoSnapshot();
    setState(() {
      _hiddenRows.clear();
    });
    _invalidateInventoryRowCache();
    _markDirty();
  }

  /// Find hidden columns adjacent to colIndex
  List<int> _findHiddenColumnsNear(int colIndex) {
    final List<int> result = [];

    // Check left
    for (int c = colIndex - 1; c >= 0; c--) {
      if (_isColumnHidden(c)) {
        result.add(c);
      } else {
        break;
      }
    }

    // Check right
    for (int c = colIndex + 1; c < _columns.length; c++) {
      if (_isColumnHidden(c)) {
        result.add(c);
      } else {
        break;
      }
    }

    return result;
  }

  /// Find hidden rows adjacent to rowIndex
  List<int> _findHiddenRowsNear(int rowIndex) {
    final List<int> result = [];

    // Check above
    for (int r = rowIndex - 1; r >= 0; r--) {
      if (_isRowHidden(r)) {
        result.add(r);
      } else {
        break;
      }
    }

    // Check below
    for (int r = rowIndex + 1; r < _data.length; r++) {
      if (_isRowHidden(r)) {
        result.add(r);
      } else {
        break;
      }
    }

    return result;
  }

  /// Clear current selection
  void _clearSelection() {
    _selectedRow = null;
    _selectedCol = null;
    _selectionEndRow = null;
    _selectionEndCol = null;
    _updateFormulaBar();
  }

  /// Get cell reference string (e.g., "A1", "B3")
  String _getCellReference(int row, int col) {
    String colRef = '';
    int c = col;
    while (c >= 0) {
      colRef = String.fromCharCode(65 + (c % 26)) + colRef;
      c = (c ~/ 26) - 1;
    }
    return '$colRef${_displayRowNumber(row)}';
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
      _suppressFormulaBarChanged = true;
      _formulaBarController.text = value; // shows raw formula or plain value
      _suppressFormulaBarChanged = false;
    } else {
      _suppressFormulaBarChanged = true;
      _formulaBarController.text = '';
      _suppressFormulaBarChanged = false;
    }
  }

  // =============== Context Menu Methods ===============

  /// Show context menu for data cells
  Future<void> _showCellContextMenu(
      BuildContext context, Offset position, int row, int col) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final menuItemColor = isDark ? const Color(0xFFE5E7EB) : Colors.black87;
    final commentKey = _inventoryCommentKey();
    final titleKey = _inventoryNoteTitleKey();
    final typeKey = _inventoryNoteTypeKey();
    final bool hasInventoryNote = _isInventoryTrackerSheet() &&
        (((_data[row][commentKey] ?? '').trim().isNotEmpty) ||
            ((_data[row][titleKey] ?? '').trim().isNotEmpty));

    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        if (_isInventoryTrackerSheet())
          PopupMenuItem(
            value: 'row_note',
            child: Row(
              children: [
                Icon(Icons.note_alt_outlined, size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Row Note', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (hasInventoryNote)
          PopupMenuItem(
            value: 'remove_row_note',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Remove Note', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (_isInventoryTrackerSheet()) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'hide_row',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16, color: menuItemColor),
              const SizedBox(width: 8),
              Text('Hide Row', style: TextStyle(color: menuItemColor)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'hide_column',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16, color: menuItemColor),
              const SizedBox(width: 8),
              Text('Hide Column', style: TextStyle(color: menuItemColor)),
            ],
          ),
        ),
        if (_hiddenRows.isNotEmpty || _hiddenColumns.isNotEmpty)
          const PopupMenuDivider(),
        if (_hiddenRows.isNotEmpty)
          PopupMenuItem(
            value: 'unhide_all_rows',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide All Rows', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (_hiddenColumns.isNotEmpty)
          PopupMenuItem(
            value: 'unhide_all_columns',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide All Columns',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
      ],
    );

    if (result == null) return;

    switch (result) {
      case 'row_note':
        await _showInventoryRowCommentDialog(row);
        break;
      case 'remove_row_note':
        _ensureInventoryCommentColumn();
        _pushUndoSnapshot();
        setState(() {
          _data[row][commentKey] = '';
          _data[row][titleKey] = '';
          _data[row][typeKey] = '';
        });
        if (_currentSheet != null) {
          SocketService.instance.cellUpdate(
            _currentSheet!.id,
            row,
            commentKey,
            '',
          );
          SocketService.instance.cellUpdate(
            _currentSheet!.id,
            row,
            titleKey,
            '',
          );
          SocketService.instance.cellUpdate(
            _currentSheet!.id,
            row,
            typeKey,
            '',
          );
        }
        _markDirty();
        break;
      case 'hide_row':
        _pushUndoSnapshot();
        setState(() {
          _hiddenRows.add(row);
          _clearSelection();
        });
        _markDirty();
        break;
      case 'hide_column':
        _pushUndoSnapshot();
        setState(() {
          _hiddenColumns.add(col);
          _clearSelection();
        });
        _invalidateInventoryColumnCache();
        _markDirty();
        break;
      case 'unhide_all_rows':
        _unhideAllRows();
        break;
      case 'unhide_all_columns':
        _unhideAllColumns();
        break;
    }
  }

  /// Show context menu for column headers
  Future<void> _showColumnHeaderContextMenu(
      BuildContext context, Offset position, int colIndex) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final menuItemColor = isDark ? const Color(0xFFE5E7EB) : Colors.black87;

    final String colKey =
        (colIndex >= 0 && colIndex < _columns.length) ? _columns[colIndex] : '';
    final bool isInventory = _isInventoryTrackerSheet();
    final bool isInvDateCol = isInventory &&
        colKey.startsWith('DATE:') &&
        colKey.split(':').length == 3;
    final String? invDateStr = isInvDateCol ? colKey.split(':')[1] : null;
    final String invDateLabel =
        invDateStr == null ? '' : _inventoryDateLabel(invDateStr);

    final List<String> allInvDates =
        isInventory ? _inventoryAllDates() : const [];
    final bool canHideAnyInvDates =
        isInventory && allInvDates.any(_inventoryDateHasAnyVisibleSubcolumns);
    final bool canUnhideAnyInvDates =
        isInventory && allInvDates.any(_inventoryDateHasAnyHiddenSubcolumns);
    final bool invThisDateHasHidden =
        invDateStr != null && _inventoryDateHasAnyHiddenSubcolumns(invDateStr);
    final bool invThisDateHasVisible =
        invDateStr != null && _inventoryDateHasAnyVisibleSubcolumns(invDateStr);

    final adjacentHidden = _findHiddenColumnsNear(colIndex);
    final hasHiddenLeft = adjacentHidden.any((c) => c < colIndex);
    final hasHiddenRight = adjacentHidden.any((c) => c > colIndex);

    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        if (_canEditSheet())
          PopupMenuItem(
            value: 'rename',
            child: Row(
              children: [
                Icon(Icons.drive_file_rename_outline,
                    size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Rename Column', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (_canEditSheet()) const PopupMenuDivider(),
        PopupMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16, color: menuItemColor),
              const SizedBox(width: 8),
              Text('Hide Column', style: TextStyle(color: menuItemColor)),
            ],
          ),
        ),

        // Inventory Tracker date helpers (bulk hide/unhide)
        if (isInventory && (canHideAnyInvDates || canUnhideAnyInvDates))
          const PopupMenuDivider(),
        if (isInvDateCol && invDateStr != null && invThisDateHasVisible)
          PopupMenuItem(
            value: 'inv_hide_this_date',
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Hide Date $invDateLabel',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (isInvDateCol && invDateStr != null && invThisDateHasHidden)
          PopupMenuItem(
            value: 'inv_unhide_this_date',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide Date $invDateLabel',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (canHideAnyInvDates)
          PopupMenuItem(
            value: 'inv_hide_dates',
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Hide Dates…', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (canHideAnyInvDates)
          PopupMenuItem(
            value: 'inv_hide_all_dates',
            child: Row(
              children: [
                Icon(Icons.visibility_off_outlined,
                    size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Hide All Dates', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (canUnhideAnyInvDates)
          PopupMenuItem(
            value: 'inv_unhide_dates',
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 16, color: menuItemColor),
                const SizedBox(width: 8),
                Text('Unhide Dates…', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (canUnhideAnyInvDates)
          PopupMenuItem(
            value: 'inv_unhide_all_dates',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide All Dates',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),

        if (hasHiddenLeft || hasHiddenRight) const PopupMenuDivider(),
        if (hasHiddenLeft)
          PopupMenuItem(
            value: 'unhide_left',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide Left Columns',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (hasHiddenRight)
          PopupMenuItem(
            value: 'unhide_right',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide Right Columns',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (_hiddenColumns.isNotEmpty)
          PopupMenuItem(
            value: 'unhide_all',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide All Columns',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
      ],
    );

    if (result == null) return;

    switch (result) {
      case 'rename':
        await _renameColumn(colIndex);
        break;
      case 'hide':
        _pushUndoSnapshot();
        setState(() {
          _hiddenColumns.add(colIndex);
          _clearSelection();
        });
        _invalidateInventoryColumnCache();
        _markDirty();
        break;
      case 'inv_hide_this_date':
        if (invDateStr != null) {
          _hideInventoryDates([invDateStr]);
        }
        break;
      case 'inv_unhide_this_date':
        if (invDateStr != null) {
          _unhideInventoryDates([invDateStr]);
        }
        break;
      case 'inv_hide_dates':
        await _showInventoryHideDatesDialog();
        break;
      case 'inv_unhide_dates':
        await _showInventoryUnhideDatesDialog();
        break;
      case 'inv_hide_all_dates':
        _hideInventoryDates(allInvDates);
        break;
      case 'inv_unhide_all_dates':
        _unhideInventoryDates(allInvDates);
        break;
      case 'unhide_left':
        _pushUndoSnapshot();
        setState(() {
          for (final c in adjacentHidden) {
            if (c < colIndex) _hiddenColumns.remove(c);
          }
        });
        _invalidateInventoryColumnCache();
        _markDirty();
        break;
      case 'unhide_right':
        _pushUndoSnapshot();
        setState(() {
          for (final c in adjacentHidden) {
            if (c > colIndex) _hiddenColumns.remove(c);
          }
        });
        _invalidateInventoryColumnCache();
        _markDirty();
        break;
      case 'unhide_all':
        _unhideAllColumns();
        break;
    }
  }

  /// Show context menu for row headers
  Future<void> _showRowHeaderContextMenu(
      BuildContext context, Offset position, int rowIndex) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final menuBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final menuItemColor = isDark ? const Color(0xFFE5E7EB) : Colors.black87;

    final adjacentHidden = _findHiddenRowsNear(rowIndex);
    final hasHiddenAbove = adjacentHidden.any((r) => r < rowIndex);
    final hasHiddenBelow = adjacentHidden.any((r) => r > rowIndex);

    final RenderBox? overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        overlay.size.width - position.dx,
        overlay.size.height - position.dy,
      ),
      color: menuBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'hide',
          child: Row(
            children: [
              Icon(Icons.visibility_off, size: 16, color: menuItemColor),
              const SizedBox(width: 8),
              Text('Hide Row', style: TextStyle(color: menuItemColor)),
            ],
          ),
        ),
        if (hasHiddenAbove || hasHiddenBelow) const PopupMenuDivider(),
        if (hasHiddenAbove)
          PopupMenuItem(
            value: 'unhide_above',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide Above Rows',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (hasHiddenBelow)
          PopupMenuItem(
            value: 'unhide_below',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide Below Rows',
                    style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
        if (_hiddenRows.isNotEmpty)
          PopupMenuItem(
            value: 'unhide_all',
            child: Row(
              children: [
                const Icon(Icons.visibility, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text('Unhide All Rows', style: TextStyle(color: menuItemColor)),
              ],
            ),
          ),
      ],
    );

    if (result == null) return;

    switch (result) {
      case 'hide':
        _pushUndoSnapshot();
        setState(() {
          _hiddenRows.add(rowIndex);
          _clearSelection();
        });
        _markDirty();
        break;
      case 'unhide_above':
        _pushUndoSnapshot();
        setState(() {
          for (final r in adjacentHidden) {
            if (r < rowIndex) _hiddenRows.remove(r);
          }
        });
        _markDirty();
        break;
      case 'unhide_below':
        _pushUndoSnapshot();
        setState(() {
          for (final r in adjacentHidden) {
            if (r > rowIndex) _hiddenRows.remove(r);
          }
        });
        _markDirty();
        break;
      case 'unhide_all':
        _unhideAllRows();
        break;
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

  void _handleEditTab({required bool backwards}) {
    if (!mounted) return;
    if (_editingRow == null || _editingCol == null) return;

    final row = _editingRow!;
    final col = _editingCol!;
    _saveEdit();

    if (backwards) {
      if (col > 0) {
        _selectCell(row, col - 1);
      } else if (row > 0) {
        _selectCell(row - 1, _columns.isEmpty ? 0 : (_columns.length - 1));
      }
    } else {
      if (col < _columns.length - 1) {
        _selectCell(row, col + 1);
      } else if (row < _data.length - 1) {
        _selectCell(row + 1, 0);
      }
    }

    _spreadsheetFocusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (!mounted) return KeyEventResult.handled;

    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;

    final key = event.logicalKey;

    // Undo / Redo shortcuts (global in sheet view)
    if (isCtrl && key == LogicalKeyboardKey.keyZ) {
      if (isShift) {
        _redo();
      } else {
        _undo();
      }
      return KeyEventResult.handled;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyY) {
      _redo();
      return KeyEventResult.handled;
    }

    // If the spreadsheet has focus but no cell is selected yet, arrow keys can
    // fall through to Flutter's directional focus traversal. That traversal can
    // crash when the tree is mid-update ("inactive element").
    final isNavKey = key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end ||
        key == LogicalKeyboardKey.tab;
    if ((_selectedRow == null || _selectedCol == null) && isNavKey) {
      _selectCell(0, 0);
      return KeyEventResult.handled;
    }

    if (_editingRow != null && _editingCol != null) {
      // In editing mode
      if (key == LogicalKeyboardKey.escape) {
        _cancelEdit();
        _spreadsheetFocusNode.requestFocus();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.enter) {
        final row = _editingRow!;
        final col = _editingCol!;
        _saveEdit();
        // Move to next row
        if (row < _data.length - 1) {
          _selectCell(row + 1, col);
        }
        _spreadsheetFocusNode.requestFocus();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.tab) {
        _handleEditTab(backwards: isShift);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    } else if (_selectedRow != null && _selectedCol != null) {
      // In selection mode

      // Ctrl+A: Select all cells
      if (isCtrl && key == LogicalKeyboardKey.keyA) {
        setState(() {
          _selectedRow = 0;
          _selectedCol = 0;
          _selectionEndRow = _data.length - 1;
          _selectionEndCol = _columns.length - 1;
        });
        return KeyEventResult.handled;
      }

      // Ctrl+C: Copy selected cells
      if (isCtrl && key == LogicalKeyboardKey.keyC) {
        _copySelection();
        return KeyEventResult.handled;
      }

      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.f2) {
        _startEditing(_selectedRow!, _selectedCol!);
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowUp) {
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
      } else if (key == LogicalKeyboardKey.arrowDown) {
        if (isShift) {
          final endRow = (_selectionEndRow ?? _selectedRow!) + 1;
          if (endRow < _data.length) {
            setState(() => _selectionEndRow = endRow);
          }
        } else if (_selectedRow! < _data.length - 1) {
          _selectCell(_selectedRow! + 1, _selectedCol!);
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        if (isShift) {
          final endCol = (_selectionEndCol ?? _selectedCol!) - 1;
          if (endCol >= 0) {
            setState(() => _selectionEndCol = endCol);
          }
        } else if (_selectedCol! > 0) {
          _selectCell(_selectedRow!, _selectedCol! - 1);
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        if (isShift) {
          final endCol = (_selectionEndCol ?? _selectedCol!) + 1;
          if (endCol < _columns.length) {
            setState(() => _selectionEndCol = endCol);
          }
        } else if (_selectedCol! < _columns.length - 1) {
          _selectCell(_selectedRow!, _selectedCol! + 1);
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.tab) {
        if (isShift) {
          if (_selectedCol! > 0) {
            _selectCell(_selectedRow!, _selectedCol! - 1);
          } else if (_selectedRow! > 0) {
            _selectCell(_selectedRow! - 1,
                _columns.isEmpty ? 0 : (_columns.length - 1));
          }
        } else {
          if (_selectedCol! < _columns.length - 1) {
            _selectCell(_selectedRow!, _selectedCol! + 1);
          } else if (_selectedRow! < _data.length - 1) {
            _selectCell(_selectedRow! + 1, 0);
          }
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.backspace) {
        _clearSelectedCells();
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.home) {
        if (isCtrl) {
          _selectCell(0, 0);
        } else {
          _selectCell(_selectedRow!, 0);
        }
        return KeyEventResult.handled;
      } else if (key == LogicalKeyboardKey.end) {
        if (isCtrl) {
          _selectCell(_data.length - 1, _columns.length - 1);
        } else {
          _selectCell(_selectedRow!, _columns.length - 1);
        }
        return KeyEventResult.handled;
      } else {
        // Start editing on any printable key press
        final character = event.character;
        if (character != null && character.length == 1 && !isCtrl) {
          _startEditing(_selectedRow!, _selectedCol!);
          _editController.text = character;
          _editController.selection =
              TextSelection.collapsed(offset: character.length);
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
    _stopLiveTyping();

    for (final t in _inventoryTotalsRecalcTimers.values) {
      t.cancel();
    }
    _inventoryTotalsRecalcTimers.clear();
    _pendingRemoteTypingFlush?.cancel();
    _pendingRemoteTypingFlush = null;
    _pendingRemoteTypingCells.clear();

    if (_currentSheet != null) {
      SocketService.instance.leaveSheet(_currentSheet!.id);
    }
    SocketService.instance.clearCallbacks();
    _editController.removeListener(_onLocalEditControllerChanged);
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
      color: Colors.black.withValues(alpha: 0.04),
      blurRadius: 14,
      offset: const Offset(0, 4),
    );
    final hoverShadow = BoxShadow(
      color: Colors.black.withValues(alpha: 0.07),
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
                                            ? _kBlue.withValues(alpha: 0.35)
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

      // Prefetch discrepancy badges for any Inventory Tracker sheets in this folder.
      _prefetchInventoryNoteBadges(childSheets);
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

      // Prefetch discrepancy badges for any Inventory Tracker sheets in this folder.
      _prefetchInventoryNoteBadges(childSheets);
    } catch (_) {
      // Keep it silent; the folder just won't show children.
    } finally {
      if (mounted) {
        setState(() => _explorerLoadingFolderIds.remove(folderId));
      }
    }
  }

  Future<void> _refreshAllSheetsExplorerCache() async {
    if (!mounted) return;

    // After moving sheets, the "All Sheets" tree can appear stale because
    // folder children are cached (even for folders that were expanded earlier
    // and later collapsed). Clear caches and refresh expanded nodes so the move
    // is reflected immediately without requiring manual collapse/expand.
    if (_explorerFolderCache.isNotEmpty) {
      setState(() => _explorerFolderCache.clear());
    }

    final expanded = _explorerExpandedFolderIds.toList(growable: false);
    for (final folderId in expanded) {
      await _ensureExplorerFolderLoaded(folderId, forceRefresh: true);
    }
  }

  // ── Recent sheet card ──
  Widget _buildRecentCard(SheetModel sheet) {
    final timeAgo = _timeAgo(sheet.updatedAt ?? sheet.createdAt);
    final isHovered = _hoveredRecentSheetId == sheet.id;
    final summary = _inventoryNoteSummaryBySheetId[sheet.id] ??
        const _InventoryNoteSummary(discrepancyCount: 0, commentCount: 0);

    // Ensure badge is fetched for Inventory Tracker sheets.
    _ensureInventoryNoteSummaryLoaded(sheet);

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
              color: isHovered ? _kBlue.withValues(alpha: 0.35) : _borderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isHovered ? 0.07 : 0.04),
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
                      Stack(
                        clipBehavior: Clip.none,
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
                          if (summary.hasAny)
                            Positioned(
                              right: -6,
                              top: -6,
                              child: _buildInventoryNoteBadge(
                                summary,
                                fontSize: 9,
                              ),
                            ),
                        ],
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
    final checkboxBorder = _isDark ? const Color(0xFF475569) : _borderColor;

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
            color: Colors.black.withValues(alpha: 0.04),
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
                        color: _borderColor.withValues(
                            alpha: _isDark ? 0.55 : 0.85),
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
              final folderId = (folder['id'] is int)
                  ? folder['id'] as int
                  : int.tryParse(folder['id']?.toString() ?? '') ?? -1;
              final cached = _explorerFolderCache[folderId];
              final folderDiscrepantSheets = cached == null
                  ? 0
                  : cached.sheets
                      .where((s) =>
                          (_inventoryNoteSummaryBySheetId[s.id]
                                  ?.discrepancyCount ??
                              0) >
                          0)
                      .length;

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
                          color:
                              _kBlue.withValues(alpha: _isDark ? 0.35 : 0.18),
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
                            if (folderDiscrepantSheets > 0) ...[
                              const SizedBox(width: 8),
                              _buildInventoryNoteBadge(
                                _InventoryNoteSummary(
                                  discrepancyCount: folderDiscrepantSheets,
                                  commentCount: 0,
                                ),
                                fontSize: 9,
                                tooltipOverride:
                                    'Sheets with discrepancies: $folderDiscrepantSheets',
                              ),
                            ],
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
              final summary = _inventoryNoteSummaryBySheetId[sheet.id] ??
                  const _InventoryNoteSummary(
                      discrepancyCount: 0, commentCount: 0);

              // Ensure badge is fetched for Inventory Tracker sheets.
              _ensureInventoryNoteSummaryLoaded(sheet);

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
                            if (summary.hasAny) ...[
                              const SizedBox(width: 8),
                              _buildInventoryNoteBadge(summary),
                            ],
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
                            activeColor: _kBlue,
                            checkColor: Colors.white,
                            side: BorderSide(color: checkboxBorder, width: 1.2),
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
                          : _surfaceAltColor.withValues(alpha: 0.7);

                      Color rowBg = isHovered ? _surfaceAltColor : baseAlt;

                      if (entry.kind == _ExplorerEntryKind.folder) {
                        final folderId = (entry.folder?['id'] is int)
                            ? entry.folder!['id'] as int
                            : int.tryParse(
                                entry.folder?['id']?.toString() ?? '');
                        final isFolderSelected = folderId != null &&
                            _explorerSelectedFolderIds.contains(folderId);
                        if (isFolderSelected) {
                          rowBg = _kBlue.withValues(alpha: 0.10);
                        }
                        if (entry.isExpanded == true) {
                          rowBg = _kBlue.withValues(alpha: 0.06);
                        }
                      }

                      if (entry.kind == _ExplorerEntryKind.sheet) {
                        final sheet = entry.sheet!;
                        final isSelected = _selectedSheetIds.contains(sheet.id);
                        final isOpening = _openingSheetId == sheet.id;
                        final isActiveSheet = _currentSheet?.id == sheet.id;
                        rowBg = isSelected
                            ? _kBlue.withValues(alpha: 0.10)
                            : isOpening
                                ? _kBlue.withValues(alpha: 0.08)
                                : isActiveSheet
                                    ? _kBlue.withValues(alpha: 0.06)
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
                                        activeColor: _kBlue,
                                        checkColor: Colors.white,
                                        side: BorderSide(
                                            color: checkboxBorder, width: 1.2),
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
                                    if (folderId == null) {
                                      return const SizedBox();
                                    }
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
                                        activeColor: _kBlue,
                                        checkColor: Colors.white,
                                        side: BorderSide(
                                            color: checkboxBorder, width: 1.2),
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
              final leavingId = _currentSheet?.id;
              if (leavingId != null) {
                SocketService.instance.leaveSheet(leavingId);
              }
              _stopLiveTyping();
              context.read<DataProvider>().clearCurrentSheet();
              setState(() {
                _currentSheet = null;
                _selectedRow = null;
                _selectedCol = null;
                _selectionEndRow = null;
                _selectionEndCol = null;
                _editingRow = null;
                _editingCol = null;
                _activeSheetUsers = [];
                _presenceUsers = [];
                _cellPresenceUserIds.clear();
                _presenceInfoMap.clear();
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

    final int discrepancyCount =
        _isInventoryTrackerSheet() ? _inventoryDiscrepancyNoteCount() : 0;

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
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final isDark = theme.brightness == Brightness.dark;
      final panelBg = isDark ? scheme.surfaceContainer : scheme.surface;
      final panelBorder = scheme.outlineVariant;
      final panelText = scheme.onSurface;
      final panelMutedText = scheme.onSurfaceVariant;

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
        final apiRole = (user['role'] ?? '').toString();
        final presenceRole = (fromPresence?.role ?? '').toString();
        final selfRole = ((user['is_you'] == true) ? authUser?.role : '') ?? '';
        final role = (apiRole.trim().isNotEmpty
                ? apiRole
                : (presenceRole.trim().isNotEmpty ? presenceRole : selfRole))
            .toString();

        final apiDept = (user['department_name'] ?? '').toString();
        final presenceDept = (fromPresence?.departmentName ?? '').toString();
        final department = (apiDept.trim().isNotEmpty
                ? apiDept
                : (presenceDept.trim().isNotEmpty ? presenceDept : ''))
            .toString();

        if (kDebugMode) {
          final a = apiRole.trim().toLowerCase();
          final p = presenceRole.trim().toLowerCase();
          if (a.isNotEmpty && p.isNotEmpty && a != p) {
            debugPrint(
                '[ActiveUsers] role mismatch user=$uid @$username api=$apiRole presence=$presenceRole');
          }
        }
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
            color: panelBg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: panelBorder, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group, size: 14, color: panelMutedText),
              const SizedBox(width: 6),
              Text(
                '${enriched.length} Active',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: panelText,
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
                            color: scheme.surfaceContainerHigh,
                            border: Border.all(color: panelBg, width: 1.8),
                          ),
                          child: Text(
                            '+$overflow',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: overflow > 0 ? panelMutedText : panelText,
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
                final leavingId = _currentSheet?.id;
                if (leavingId != null) {
                  SocketService.instance.leaveSheet(leavingId);
                }
                _stopLiveTyping();
                context.read<DataProvider>().clearCurrentSheet();
                setState(() {
                  _currentSheet = null;
                  _selectedRow = null;
                  _selectedCol = null;
                  _selectionEndRow = null;
                  _selectionEndCol = null;
                  _editingRow = null;
                  _editingCol = null;
                  _activeSheetUsers = [];
                  _presenceUsers = [];
                  _cellPresenceUserIds.clear();
                  _presenceInfoMap.clear();
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
              Tooltip(
                message: (!widget.readOnly && !isViewer)
                    ? 'Rename sheet'
                    : _currentSheet?.name ?? 'Untitled',
                child: InkWell(
                  onTap:
                      (!widget.readOnly && !isViewer && _currentSheet != null)
                          ? () => _renameSheet(_currentSheet!)
                          : null,
                  borderRadius: BorderRadius.circular(6),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 2, vertical: 1),
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
                  ),
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
          if (_isInventoryTrackerSheet() && discrepancyCount > 0) ...[
            const SizedBox(width: 10),
            Tooltip(
              message:
                  'This Inventory Tracker has $discrepancyCount discrepancy note(s).\nClick to sort discrepancy rows to the top.\nHover the highlighted row to view details.\nRight-click a cell in the row → Row Note to edit/remove.',
              child: InkWell(
                onTap: () {
                  if (_editingRow != null) {
                    _saveEdit();
                  }
                  setState(() {
                    _inventorySortMode = _InventorySortMode.discrepancyFirst;
                    _inventorySearchQuery = '';
                    _inventorySearchController.clear();
                  });
                  _invalidateInventoryRowCache();
                },
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  height: 22,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppColors.primaryOrange
                        .withValues(alpha: _isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: AppColors.primaryOrange
                          .withValues(alpha: _isDark ? 0.55 : 0.35),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'Discrepancy: $discrepancyCount',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryOrange,
                    ),
                  ),
                ),
              ),
            ),
          ],
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
          // ─ Center: QB Code / Material Name search bar ─
          Expanded(
            child: Center(
              child: SizedBox(
                width: 260,
                height: 32,
                child: TextField(
                  controller: _inventorySearchController,
                  decoration: InputDecoration(
                    hintText: 'Material Name or QB Code…',
                    hintStyle: TextStyle(fontSize: 12, color: _textSecondary),
                    prefixIcon: const Icon(Icons.search,
                        size: 16, color: AppColors.primaryBlue),
                    suffixIcon: _inventorySearchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.close,
                                size: 14, color: _textSecondary),
                            onPressed: () {
                              setState(() {
                                _inventorySearchQuery = '';
                                _inventorySearchController.clear();
                              });
                              _invalidateInventoryRowCache();
                            },
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
                  onChanged: (v) {
                    setState(() => _inventorySearchQuery = v.trim());
                    _invalidateInventoryRowCache();
                  },
                ),
              ),
            ),
          ),
          if (_isInventoryTrackerSheet()) ...[
            const SizedBox(width: 10),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _surfaceAltColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Filter',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _textSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<_InventorySortMode>(
                      value: _inventorySortMode,
                      icon: Icon(Icons.arrow_drop_down,
                          size: 18, color: _textSecondary),
                      style: TextStyle(fontSize: 12, color: _textPrimary),
                      onChanged: (mode) {
                        if (mode == null) return;
                        if (_editingRow != null) {
                          _saveEdit();
                        }
                        setState(() => _inventorySortMode = mode);
                        _invalidateInventoryRowCache();
                      },
                      items: _InventorySortMode.values
                          .map((m) => DropdownMenuItem<_InventorySortMode>(
                                value: m,
                                child: Text(_inventorySortLabel(m)),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
                const Spacer(),
                if (_isInventoryTrackerSheet()) ...[
                  _buildInventoryTopStockIndicators(),
                  const SizedBox(width: 12),
                ],
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
              ? (_isDark
                  ? _kBlue.withValues(alpha: 0.16)
                  : const Color(0xFFF0F4FF))
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

  Widget _buildInventoryTopStockChip({
    required IconData icon,
    required Color color,
    required String tooltip,
    required int count,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _borderColor),
          color: color.withValues(alpha: _isDark ? 0.18 : 0.10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryTopStockIndicators() {
    if (!_isInventoryTrackerSheet()) return const SizedBox();

    _ensureInventoryRowCache();
    final outCount = _inventoryCachedOutOfStockCount;
    final criticalCount = _inventoryCachedCriticalCount;
    final lowCount = _inventoryCachedLowStockCount;
    if (outCount <= 0 && criticalCount <= 0 && lowCount <= 0) {
      return const SizedBox();
    }

    final scheme = Theme.of(context).colorScheme;
    final outColor = scheme.error;
    final criticalColor = scheme.error;
    final lowColor = AppColors.primaryOrange;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (outCount > 0) ...[
          _buildInventoryTopStockChip(
            icon: Icons.report_gmailerrorred_outlined,
            color: outColor,
            tooltip: 'Out of Stock: $outCount',
            count: outCount,
          ),
          if (criticalCount > 0 || lowCount > 0) const SizedBox(width: 8),
        ],
        if (criticalCount > 0) ...[
          _buildInventoryTopStockChip(
            icon: Icons.error_outline_rounded,
            color: criticalColor,
            tooltip: 'Critical: $criticalCount',
            count: criticalCount,
          ),
          if (lowCount > 0) const SizedBox(width: 8),
        ],
        if (lowCount > 0)
          _buildInventoryTopStockChip(
            icon: Icons.warning_amber_rounded,
            color: lowColor,
            tooltip: 'Low Stock: $lowCount',
            count: lowCount,
          ),
      ],
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
    final scheme = Theme.of(context).colorScheme;

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
                color: scheme.surfaceContainerHighest,
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
                style: TextStyle(
                  fontSize: 9,
                  color: scheme.onSurfaceVariant,
                ),
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

    final scrollBehavior = ScrollConfiguration.of(context).copyWith(
      dragDevices: {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.unknown,
      },
    );

    return ScrollConfiguration(
      behavior: scrollBehavior,
      child: SingleChildScrollView(
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
                _buildRibbonButton(Icons.table_rows_outlined, '+Row',
                    canEdit ? _addRow : null),
                _buildRibbonButton(Icons.table_rows_outlined, '-Row',
                    canEdit ? _deleteRow : null),
              ]),
            // ── Merge ──
            if (!isViewer && !widget.readOnly)
              group('Merge', [
                _buildRibbonButton(
                    Icons.call_merge, 'Merge', canEdit ? _mergeCells : null),
                _buildRibbonButton(Icons.call_split, 'Unmerge',
                    canEdit ? _unmergeCells : null),
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
                  _buildRibbonButton(Icons.calendar_month, 'Add Date',
                      _addInventoryDateColumn),
                _buildRibbonButton(
                  Icons.visibility_off_outlined,
                  'Hide Dates',
                  _showInventoryHideDatesDialog,
                ),
                _buildRibbonButton(
                  Icons.visibility_outlined,
                  'Unhide Dates',
                  _showInventoryUnhideDatesDialog,
                ),
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
                  () {
                    setState(() {
                      _inventoryFilterWeek = !_inventoryFilterWeek;
                      _inventoryFilterToday = false;
                    });
                    _invalidateInventoryColumnCache();
                  },
                ),
                _buildRibbonButton(
                  Icons.warning_amber_rounded,
                  'Critical Alerts',
                  _showCriticalAlertsModal,
                ),
              ]),
          ],
        ),
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
          Icons.visibility_off_outlined,
          'Hide Dates',
          _showInventoryHideDatesDialog,
        ),
        const SizedBox(width: 6),
        _buildRibbonButton(
          Icons.visibility_outlined,
          'Unhide Dates',
          _showInventoryUnhideDatesDialog,
        ),
        const SizedBox(width: 6),
        _buildRibbonButton(
          _inventoryFilterToday ? Icons.today : Icons.today_outlined,
          _inventoryFilterToday ? 'All Dates' : 'Today',
          _scrollToInventoryToday,
        ),
        const SizedBox(width: 6),
        _buildRibbonButton(
          _inventoryFilterWeek ? Icons.calendar_view_month : Icons.date_range,
          _inventoryFilterWeek ? 'All Dates' : 'This Week',
          () {
            setState(() {
              _inventoryFilterWeek = !_inventoryFilterWeek;
              _inventoryFilterToday = false;
            });
            _invalidateInventoryColumnCache();
          },
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
      AppModal.showText(
        context,
        title: 'Error',
        message: 'Only admins can change alert settings.',
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
                  color: AppColors.primaryBlue.withValues(alpha: 0.1),
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
                _invalidateInventoryRowCache();
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
    final productKey = _inventoryProductNameKey();
    final productName =
        (productKey == null ? '' : (row[productKey] ?? '')).trim();
    final code = _inventoryRowCode(row).trim();
    if (productName.isEmpty && code.isEmpty) return null;

    double? numVal(String? key) {
      if (key == null) return null;
      final raw = (row[key] ?? '').replaceAll(',', '').trim();
      if (raw.isEmpty) return null;
      return double.tryParse(raw);
    }

    final critical = numVal(_inventoryCriticalKey());
    final totalQty = numVal(_inventoryTotalQtyKey());

    // Critical rule: item is critical when Total Quantity is at or below Critical.
    if (critical == null || totalQty == null || critical <= 0) return null;
    if (totalQty > critical) return null;

    final pct = (critical - totalQty) / critical;
    return pct.clamp(0.0, 1.0);
  }

  double? _maintainingDeficitPctForRow(Map<String, String> row) {
    final productKey = _inventoryProductNameKey();
    final productName =
        (productKey == null ? '' : (row[productKey] ?? '')).trim();
    final code = _inventoryRowCode(row).trim();
    if (productName.isEmpty && code.isEmpty) return null;

    double? numVal(String? key) {
      if (key == null) return null;
      final raw = (row[key] ?? '').replaceAll(',', '').trim();
      if (raw.isEmpty || raw == '-') return null;
      return double.tryParse(raw);
    }

    final totalQty = numVal(_inventoryTotalQtyKey());
    if (totalQty == null) return null;

    // PR / per-request items have no maintaining threshold.
    final unitKey = _inventoryMaintainingUnitKey();
    final unit = (unitKey == null ? '' : (row[unitKey] ?? ''))
        .toString()
        .trim()
        .toUpperCase();
    if (unit == 'PR') return null;

    final maintainingQtyKey = _inventoryMaintainingQtyKey();
    final maintainingQty = numVal(maintainingQtyKey) ??
        double.tryParse(
          (row['Maintaining'] ?? '').toString().replaceAll(',', '').trim(),
        );
    if (maintainingQty == null || maintainingQty <= 0) return null;
    if (totalQty > maintainingQty) return null;

    final pct = (maintainingQty - totalQty) / maintainingQty;
    return pct.clamp(0.0, 1.0);
  }

  double _inventoryLowStockScoreForRow(Map<String, String> row) {
    final criticalPct = _criticalDeficitPctForRow(row);
    if (criticalPct != null) return 2.0 + criticalPct;
    final maintainingPct = _maintainingDeficitPctForRow(row);
    if (maintainingPct != null) return 1.0 + maintainingPct;
    return 0.0;
  }

  List<Map<String, String>> _buildCriticalRows() {
    final criticalRows = <Map<String, String>>[];
    for (final row in _data) {
      final deficitPct = _criticalDeficitPctForRow(row);
      if (deficitPct == null) continue;

      final productKey = _inventoryProductNameKey();
      final stockKey = _inventoryStockKey();
      final totalKey = _inventoryTotalQtyKey();
      final maintainingQtyKey = _inventoryMaintainingQtyKey();
      final criticalKey = _inventoryCriticalKey();

      final total =
          double.tryParse(totalKey == null ? '' : (row[totalKey] ?? '')) ?? 0;
      final stock =
          double.tryParse(stockKey == null ? '' : (row[stockKey] ?? '')) ?? 0;
      final maintainingQtyRaw =
          (maintainingQtyKey == null ? '' : (row[maintainingQtyKey] ?? ''))
              .trim();
      final maintainingLegacyRaw = (row['Maintaining'] ?? '').toString();
      final maintaining = double.tryParse(
            (maintainingQtyRaw.isNotEmpty
                    ? maintainingQtyRaw
                    : maintainingLegacyRaw)
                .replaceAll(',', ''),
          ) ??
          0;
      final critical = double.tryParse(
              criticalKey == null ? '' : (row[criticalKey] ?? '')) ??
          0;
      final deficit = (critical - total).clamp(0, double.infinity);
      criticalRows.add({
        'Material Name':
            productKey == null ? '' : (row[productKey] ?? '').toString(),
        'QB Code': _inventoryRowCode(row),
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
      AppModal.showText(
        context,
        title: 'Error',
        message: 'Only admins can open critical alerts.',
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
                                      r['Material Name'] ?? '',
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
                                    color: severity.withValues(alpha: 0.12),
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
    _pushUndoSnapshot();
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
    _markDirty();
  }

  void _setFontSize(double size) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      _currentFontSize = size;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellFontSizes[_cellKey(r, c)] = size;
        }
      }
    });
    _markDirty();
  }

  void _setAlignment(TextAlign align) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellAlignments[_cellKey(r, c)] = align;
        }
      }
    });
    _markDirty();
  }

  void _setTextColor(Color color) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      _currentTextColor = color;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellTextColors[_cellKey(r, c)] = color;
        }
      }
    });
    _markDirty();
  }

  void _setBackgroundColor(Color color) {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    _pushUndoSnapshot();
    setState(() {
      _currentBackgroundColor = color;
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellBackgroundColors[_cellKey(r, c)] = color;
        }
      }
    });
    _markDirty();
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
    _pushUndoSnapshot();
    setState(() {
      for (int r = bounds['minRow']!; r <= bounds['maxRow']!; r++) {
        for (int c = bounds['minCol']!; c <= bounds['maxCol']!; c++) {
          _cellBorders[_cellKey(r, c)] = Map.from(borders);
        }
      }
    });
    _markDirty();
  }

  void _setOutsideBorders() {
    if (_selectedRow == null || _selectedCol == null) return;
    final bounds = _getSelectionBounds();
    final minRow = bounds['minRow']!;
    final maxRow = bounds['maxRow']!;
    final minCol = bounds['minCol']!;
    final maxCol = bounds['maxCol']!;

    _pushUndoSnapshot();
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
    _markDirty();
  }

  void _mergeCells() {
    if (_selectedRow == null ||
        _selectedCol == null ||
        _selectionEndRow == null ||
        _selectionEndCol == null) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Please select a range of cells to merge',
      );
      return;
    }

    final bounds = _getSelectionBounds();
    final minRow = bounds['minRow']!;
    final maxRow = bounds['maxRow']!;
    final minCol = bounds['minCol']!;
    final maxCol = bounds['maxCol']!;

    if (minRow == maxRow && minCol == maxCol) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Please select more than one cell to merge',
      );
      return;
    }

    final rangeKey = '$minRow,$minCol:$maxRow,$maxCol';
    _pushUndoSnapshot();
    setState(() {
      _mergedCellRanges.add(rangeKey);
    });
    _markDirty();
    AppModal.showText(
      context,
      title: 'Success',
      message: 'Cells merged',
    );
  }

  void _unmergeCells() {
    if (_selectedRow == null || _selectedCol == null) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Please select a merged cell to unmerge',
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
      _pushUndoSnapshot();
      setState(() {
        _mergedCellRanges.remove(rangeToRemove);
      });
      _markDirty();
      AppModal.showText(
        context,
        title: 'Success',
        message: 'Cells unmerged',
      );
    } else {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'No merged cells found at selection',
      );
    }
  }

  void _showBorderMenu() {
    if (_selectedRow == null || _selectedCol == null) {
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'Please select cells first',
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
                AppModal.showText(
                  this.context,
                  title: 'Success',
                  message: 'All borders applied',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.border_outer),
              title: const Text('Outside Borders'),
              onTap: () {
                _setOutsideBorders();
                Navigator.pop(context);
                AppModal.showText(
                  this.context,
                  title: 'Success',
                  message: 'Outside borders applied',
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
                AppModal.showText(
                  this.context,
                  title: 'Success',
                  message: 'Top border applied',
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
                AppModal.showText(
                  this.context,
                  title: 'Success',
                  message: 'Bottom border applied',
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
                AppModal.showText(
                  this.context,
                  title: 'Success',
                  message: 'Borders removed',
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
    // Formula dialog is not implemented yet.
    AppModal.showText(
      context,
      title: 'Notice',
      message: 'Formula dialog coming soon',
    );
  }

  // ignore: unused_element
  void _insertAutoSum() {
    if (_selectedRow == null || _selectedCol == null) return;
    // Insert a simple SUM formula
    _editController.text = '=SUM()';
    AppModal.showText(
      context,
      title: 'Notice',
      message: 'Auto sum added - specify range in formula bar',
    );
  }

  Widget _buildFormatToggle(
      IconData icon, String tooltip, bool active, VoidCallback onPressed) {
    final iconColor = _isDark ? const Color(0xFFE2E8F0) : _kNavy;
    final activeBg = _isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.20)
        : _kNavy.withValues(alpha: 0.12);
    final activeBorder = _isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.45)
        : _kNavy.withValues(alpha: 0.3);
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
      AppModal.showText(
        context,
        title: 'Error',
        message: 'You do not have permission to delete folders',
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
          AppModal.showText(
            context,
            title: 'Success',
            message: 'Folder deleted successfully',
          );
        }
      } catch (e) {
        if (mounted) {
          AppModal.showText(
            context,
            title: 'Error',
            message: 'Failed to delete folder: $e',
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
      AppModal.showText(
        context,
        title: 'Error',
        message: 'Formula ${index + 1}: $err',
      );
      return;
    }
    setState(() {});
    final isAssign = entry.op == '=';
    final expr = isAssign
        ? '${entry.operandCols.first}'
        : entry.operandCols.join(' ${entry.op} ');
    AppModal.showText(
      context,
      title: 'Success',
      message: 'Formula ${index + 1}: ${entry.resultCol} = $expr applied',
    );
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
      AppModal.showText(
        context,
        title: 'Error',
        message: errors.join('\n'),
      );
      return;
    }
    AppModal.showText(
      context,
      title: 'Success',
      message: '${_cfFormulas.length} formula(s) applied',
    );
    _markDirty();
    _saveSheet();
  }

  void _clearColumnFormula() {
    setState(() => _cfFormulas = [_FormulaEntry()]);
  }

  // ── Ribbon sub-widgets ──
  Widget _buildRibbonButton(
      IconData icon, String label, VoidCallback? onPressed) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final fg = enabled
        ? scheme.onSurface
        : scheme.onSurfaceVariant.withValues(alpha: _isDark ? 0.55 : 0.65);
    final hover = scheme.surfaceContainerHighest;
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
      AppModal.showText(
        context,
        title: 'Success',
        message: 'Admin approved your edit request for cell $cellRef. '
            'The value has been applied.',
      );
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
      // No modal here. The HTTP submit path already shows confirmation.
      // Keeping this handler silent prevents duplicate dialogs if any caller
      // still uses the socket-based submit flow.
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
            _rowLabels.add(_defaultRowLabel(_data.length - 1));
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

        if (_isInventoryTrackerSheet()) {
          _inventoryStockCountsDirty = true;
        }
        // Recalculate computed columns (e.g. Total Quantity) after remote edits
        if (_isInventoryTrackerSheet() &&
            _isInventoryTotalsInputColumn(colName)) {
          _scheduleInventoryTotalsRecalcForRow(rowIndex);
        }
      } catch (e) {
        debugPrint('[onCellUpdated] error – falling back to full reload: $e');
        _reloadSheetDataOnly();
      }
    };

    // ── Live typing preview: apply remote per-keystroke text instantly ──
    socket.onCellTyping = (data) {
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

        // Don't clobber the local editor if we are currently editing this cell.
        if (_editingRow == rowIndex &&
            _editingCol != null &&
            _editingCol! >= 0 &&
            _editingCol! < _columns.length &&
            _columns[_editingCol!] == colName) {
          return;
        }

        // Inventory Tracker can be very large and rebuilds are expensive.
        // Coalesce remote typing into a single setState every ~50ms.
        if (_isInventoryTrackerSheet()) {
          _queueRemoteTypingUpdate(
            sheetId: sheetId,
            rowIndex: rowIndex,
            colName: colName,
            value: value,
          );
          return;
        }

        bool shouldUpdateFormulaBar = false;
        setState(() {
          while (_data.length <= rowIndex) {
            final emptyRow = <String, String>{};
            for (final c in _columns) {
              emptyRow[c] = '';
            }
            _data.add(emptyRow);
            _rowLabels.add(_defaultRowLabel(_data.length - 1));
          }
          if (!_columns.contains(colName)) {
            _columns.add(colName);
            for (final r in _data) {
              r.putIfAbsent(colName, () => '');
            }
          }
          _data[rowIndex][colName] = value;
          if (_selectedRow == rowIndex &&
              _selectedCol != null &&
              _selectedCol! >= 0 &&
              _selectedCol! < _columns.length &&
              _columns[_selectedCol!] == colName) {
            shouldUpdateFormulaBar = true;
          }
        });
        if (shouldUpdateFormulaBar) _updateFormulaBar();

        if (_isInventoryTrackerSheet() &&
            _isInventoryTotalsInputColumn(colName)) {
          _scheduleInventoryTotalsRecalcForRow(rowIndex);
        }
      } catch (e) {
        debugPrint('[onCellTyping] error: $e');
      }
    };

    // ── Edit canceled: revert remote preview to original text ──
    socket.onCellCanceled = (data) {
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

        bool shouldUpdateFormulaBar = false;
        setState(() {
          while (_data.length <= rowIndex) {
            final emptyRow = <String, String>{};
            for (final c in _columns) {
              emptyRow[c] = '';
            }
            _data.add(emptyRow);
            _rowLabels.add(_defaultRowLabel(_data.length - 1));
          }
          if (!_columns.contains(colName)) {
            _columns.add(colName);
            for (final r in _data) {
              r.putIfAbsent(colName, () => '');
            }
          }
          _data[rowIndex][colName] = value;
          if (_selectedRow == rowIndex &&
              _selectedCol != null &&
              _selectedCol! >= 0 &&
              _selectedCol! < _columns.length &&
              _columns[_selectedCol!] == colName) {
            shouldUpdateFormulaBar = true;
          }
        });

        if (_isInventoryTrackerSheet()) {
          _inventoryStockCountsDirty = true;
        }
        if (shouldUpdateFormulaBar) _updateFormulaBar();

        if (_isInventoryTrackerSheet() &&
            _isInventoryTotalsInputColumn(colName)) {
          _recalcInventoryTotalsForRow(rowIndex);
        }
      } catch (e) {
        debugPrint('[onCellCanceled] error: $e');
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
          _rowLabels = List.generate(_data.length, (i) => _defaultRowLabel(i));
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
                  inputFormatters: (_isInventoryTrackerSheet() &&
                          colName.startsWith('DATE:') &&
                          (colName.endsWith(':IN') || colName.endsWith(':OUT')))
                      ? <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly
                        ]
                      : null,
                  keyboardType: (_isInventoryTrackerSheet() &&
                          colName.startsWith('DATE:') &&
                          (colName.endsWith(':IN') || colName.endsWith(':OUT')))
                      ? const TextInputType.numberWithOptions(signed: false)
                      : TextInputType.text,
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

      // Inventory Tracker guard: don't allow submitting invalid IN/OUT values.
      if (_isInventoryDateQtyEditInvalid(
        rowIndex: row,
        colName: colName,
        proposedValueRaw: proposedValue,
      )) {
        AppModal.showText(
          context,
          title: 'Invalid Amount',
          message:
              'Request not submitted. Only whole numbers are allowed. IN/OUT must be 0 or more, and OUT cannot make total quantity negative.',
        );
        proposedCtrl.dispose();
        return;
      }

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
        if (mounted) {
          AppModal.showText(
            context,
            title: 'Notice',
            message: 'Edit request submitted. Waiting for admin approval.',
          );
        }
      } catch (e) {
        if (mounted) {
          AppModal.showText(
            context,
            title: 'Error',
            message: 'Failed to submit request: $e',
          );
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
                                  AppModal.showText(
                                    context,
                                    title: 'Success',
                                    message: 'Request approved.',
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
                                  AppModal.showText(
                                    context,
                                    title: 'Notice',
                                    message: 'Request rejected.',
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
        AppModal.showText(
          context,
          title: 'Error',
          message: 'Failed to load requests: $e',
        );
      }
    }
  }

  // ═══════════════════════════════════════════════════════
  //  Inventory Tracker – Dynamic Date Column Feature
  // ═══════════════════════════════════════════════════════

  static const double _invSubColW = 72.0; // width per IN/OUT sub-column
  static const double _invFixedColW = 120.0; // width for fixed columns
  static const double _invMinHeaderRowH = 18.0;
  static const double _invMaxHeaderRowH = 120.0;

  // Inventory header is 2 rows tall and is user-resizable.
  // Row 1 = date-group header; Row 2 = IN/OUT sub-header.
  double _invHeaderH1 = 32.0;
  double _invHeaderH2 = 26.0;

  bool _isResizingInvHeader = false;
  bool _isResizingInvHeaderDivider = false;
  double _invHeaderResizeStartY = 0;
  double _invHeaderResizeStartH1 = 0;
  double _invHeaderResizeStartH2 = 0;

  // Inventory column key encoding:
  // Persist a stable semantic column id while allowing the display header
  // text to be renamed.
  // Stored key format: INV:<id>|<display>
  static const String _kInvColPrefix = 'INV:';
  static const String _kInvColSep = '|';

  bool _isInvEncodedColumnKey(String key) {
    return key.startsWith(_kInvColPrefix) && key.contains(_kInvColSep);
  }

  String? _invColumnId(String key) {
    if (!_isInvEncodedColumnKey(key)) return null;
    final start = _kInvColPrefix.length;
    final sep = key.indexOf(_kInvColSep, start);
    if (sep <= start) return null;
    return key.substring(start, sep);
  }

  String _invColumnDisplay(String key) {
    if (!_isInvEncodedColumnKey(key)) return key;
    final sep = key.indexOf(_kInvColSep);
    if (sep < 0 || sep + 1 >= key.length) return key;
    return key.substring(sep + 1);
  }

  String _invEncodeColKey(String id, String display) {
    return '$_kInvColPrefix$id$_kInvColSep$display';
  }

  /// Returns the display/header label for a stored column key.
  String _displayColumnName(String storedKey) {
    return _isInvEncodedColumnKey(storedKey)
        ? _invColumnDisplay(storedKey)
        : storedKey;
  }

  String? _findInvColKeyById(String id) {
    for (final c in _columns) {
      if (_invColumnId(c) == id) return c;
    }
    return null;
  }

  String? _inventoryProductNameKey() {
    return _findInvColKeyById('product_name') ??
        (_columns.contains('Material Name')
            ? 'Material Name'
            : (_columns.contains('Product Name') ? 'Product Name' : null));
  }

  String? _inventoryCodeKey() {
    final encoded = _findInvColKeyById('code');
    if (encoded != null) return encoded;
    if (_columns.contains('QB Code')) return 'QB Code';
    if (_columns.contains('QC Code')) return 'QC Code';
    return null;
  }

  String? _inventoryTotalQtyKey() {
    return _findInvColKeyById('total_qty') ??
        (_columns.contains('Total Quantity') ? 'Total Quantity' : null);
  }

  String? _inventoryStockKey() {
    return _findInvColKeyById('stock') ??
        (_columns.contains('Stock') ? 'Stock' : null);
  }

  String? _inventoryMaintainingQtyKey() {
    return _findInvColKeyById('maintaining_qty') ??
        (_columns.contains('Maintaining Qty') ? 'Maintaining Qty' : null);
  }

  String? _inventoryMaintainingUnitKey() {
    return _findInvColKeyById('maintaining_unit') ??
        (_columns.contains('Maintaining Unit') ? 'Maintaining Unit' : null);
  }

  String? _inventoryCriticalKey() {
    return _findInvColKeyById('critical') ??
        (_columns.contains('Critical') ? 'Critical' : null);
  }

  String _inventoryCommentKey() {
    return _findInvColKeyById('comment') ?? _kInventoryCommentCol;
  }

  String _inventoryNoteTypeKey() {
    return _findInvColKeyById('note_type') ?? _kInventoryNoteTypeCol;
  }

  String _inventoryNoteTitleKey() {
    return _findInvColKeyById('note_title') ?? _kInventoryNoteTitleCol;
  }

  /// Migrates legacy Inventory Tracker column keys to encoded keys (INV:id|Label)
  /// so headers can be renamed without breaking Inventory Tracker features.
  /// Returns true if any changes were applied.
  // ignore: unused_element
  bool _migrateInventoryColumnsToEncodedIfNeeded() {
    // If any inventory columns are already encoded, assume migration completed.
    if (_columns.any(_isInvEncodedColumnKey)) return false;

    final productKey = _columns.contains('Material Name')
        ? 'Material Name'
        : (_columns.contains('Product Name') ? 'Product Name' : null);
    final codeKey = _columns.contains('QB Code')
        ? 'QB Code'
        : (_columns.contains('QC Code') ? 'QC Code' : null);
    final totalKey =
        _columns.contains('Total Quantity') ? 'Total Quantity' : null;

    // Not an Inventory Tracker sheet by legacy signature.
    if (productKey == null || codeKey == null || totalKey == null) {
      return false;
    }

    final renameMap = <String, String>{
      productKey: _invEncodeColKey('product_name', 'Material Name'),
      codeKey: _invEncodeColKey('code', codeKey),
      'Stock': _invEncodeColKey('stock', 'Stock'),
      'Maintaining Qty': _invEncodeColKey('maintaining_qty', 'Maintaining Qty'),
      'Maintaining Unit':
          _invEncodeColKey('maintaining_unit', 'Maintaining Unit'),
      'Critical': _invEncodeColKey('critical', 'Critical'),
      'Total Quantity': _invEncodeColKey('total_qty', 'Total Quantity'),
      _kInventoryCommentCol: _invEncodeColKey('comment', 'Comment'),
      _kInventoryNoteTypeCol: _invEncodeColKey('note_type', 'Note Type'),
      _kInventoryNoteTitleCol: _invEncodeColKey('note_title', 'Note Title'),
    };

    bool changed = false;

    // Update column list.
    for (int i = 0; i < _columns.length; i++) {
      final oldKey = _columns[i];
      final newKey = renameMap[oldKey];
      if (newKey == null) continue;
      if (newKey == oldKey) continue;
      _columns[i] = newKey;
      changed = true;
    }

    if (!changed) return false;

    // Update row maps.
    for (final row in _data) {
      for (final entry in renameMap.entries) {
        final oldKey = entry.key;
        final newKey = entry.value;
        if (!row.containsKey(oldKey) || row.containsKey(newKey)) continue;
        row[newKey] = row[oldKey] ?? '';
        row.remove(oldKey);
      }
    }

    return true;
  }

  String _inventoryRowCode(Map<String, String> row) {
    final codeKey = _inventoryCodeKey();
    return codeKey == null ? '' : (row[codeKey] ?? '').toString();
  }

  /// Returns true when the open sheet is an Inventory Tracker sheet.
  bool _isInventoryTrackerSheet() {
    final hasProduct = _inventoryProductNameKey() != null;
    final hasCode = _inventoryCodeKey() != null;
    final hasQty =
        _inventoryStockKey() != null || _inventoryTotalQtyKey() != null;
    return hasProduct && hasCode && hasQty;
  }

  List<String> _inventoryFrozenLeft() {
    final productKey = _inventoryProductNameKey();
    final codeCol = _inventoryCodeKey();
    final stockKey = _findInvColKeyById('stock') ??
        (_columns.contains('Stock') ? 'Stock' : null);
    final qtyKey = _findInvColKeyById('maintaining_qty') ??
        (_columns.contains('Maintaining Qty') ? 'Maintaining Qty' : null);
    final unitKey = _findInvColKeyById('maintaining_unit') ??
        (_columns.contains('Maintaining Unit') ? 'Maintaining Unit' : null);
    final criticalKey = _findInvColKeyById('critical') ??
        (_columns.contains('Critical') ? 'Critical' : null);
    return [
      if (productKey != null) productKey,
      if (codeCol != null) codeCol,
      if (stockKey != null) stockKey,
      if (qtyKey != null) qtyKey,
      if (unitKey != null) unitKey,
      if (criticalKey != null) criticalKey,
    ];
  }

  List<String> _inventoryFrozenRight() {
    final totalKey = _inventoryTotalQtyKey();
    return [if (totalKey != null) totalKey];
  }

  /// Columns that are neither frozen nor date columns.
  static const _kLegacyInventoryCols = {'Reference No.', 'Remarks'};
  static const String _kInventoryCommentCol = 'Comment';
  static const String _kInventoryNoteTypeCol = 'Note Type';
  static const String _kInventoryNoteTitleCol = 'Note Title';

  static const String _kInventoryNoteTypeDiscrepancy = 'discrepancy';
  static const String _kInventoryNoteTypeComment = 'comment';

  bool _inventoryRowHasDiscrepancy(Map<String, String> row) {
    final commentKey = _inventoryCommentKey();
    final titleKey = _inventoryNoteTitleKey();
    final typeKey = _inventoryNoteTypeKey();
    final body = (row[commentKey] ?? '').toString().trim();
    final title = (row[titleKey] ?? '').toString().trim();
    final hasNote = body.isNotEmpty || title.isNotEmpty;
    if (!hasNote) return false;

    final rawType = (row[typeKey] ?? '').toString().trim();
    final type = rawType.toLowerCase();

    // Legacy notes (no type saved) are treated as discrepancy.
    return type.isEmpty || type == _kInventoryNoteTypeDiscrepancy;
  }

  int _inventoryDiscrepancyNoteCount() {
    if (!_isInventoryTrackerSheet()) return 0;

    int count = 0;
    for (final row in _data) {
      if (_inventoryRowHasDiscrepancy(row)) {
        count++;
      }
    }
    return count;
  }

  void _ensureInventoryCommentColumn() {
    if (!_isInventoryTrackerSheet()) return;

    final bool hasEncodedInventoryCols = _columns.any(_isInvEncodedColumnKey);
    final desiredCommentKey = hasEncodedInventoryCols
        ? (_findInvColKeyById('comment') ??
            _invEncodeColKey('comment', _kInventoryCommentCol))
        : _kInventoryCommentCol;
    final desiredTypeKey = hasEncodedInventoryCols
        ? (_findInvColKeyById('note_type') ??
            _invEncodeColKey('note_type', _kInventoryNoteTypeCol))
        : _kInventoryNoteTypeCol;
    final desiredTitleKey = hasEncodedInventoryCols
        ? (_findInvColKeyById('note_title') ??
            _invEncodeColKey('note_title', _kInventoryNoteTitleCol))
        : _kInventoryNoteTitleCol;

    final needsComment = !_columns.contains(desiredCommentKey);
    final needsType = !_columns.contains(desiredTypeKey);
    final needsTitle = !_columns.contains(desiredTitleKey);
    if (!needsComment && !needsType && !needsTitle) return;

    setState(() {
      // Ensure the note columns exist and stay grouped near Product Name.
      final productKey = _inventoryProductNameKey();
      final anchor = productKey != null ? _columns.indexOf(productKey) : -1;
      int insertAt = anchor >= 0 ? (anchor + 1) : 1;

      if (!_columns.contains(desiredCommentKey)) {
        _columns.insert(insertAt.clamp(0, _columns.length), desiredCommentKey);
      }
      final commentIdx = _columns.indexOf(desiredCommentKey);
      insertAt = commentIdx >= 0 ? (commentIdx + 1) : insertAt;

      if (!_columns.contains(desiredTypeKey)) {
        _columns.insert(insertAt.clamp(0, _columns.length), desiredTypeKey);
      }
      final typeIdx = _columns.indexOf(desiredTypeKey);
      insertAt = typeIdx >= 0 ? (typeIdx + 1) : insertAt;

      if (!_columns.contains(desiredTitleKey)) {
        _columns.insert(insertAt.clamp(0, _columns.length), desiredTitleKey);
      }

      for (final row in _data) {
        row.putIfAbsent(desiredCommentKey, () => '');
        row.putIfAbsent(desiredTypeKey, () => '');
        row.putIfAbsent(desiredTitleKey, () => '');
      }
    });

    _markDirty();
  }

  Future<void> _showInventoryRowCommentDialog(int rowIndex) async {
    if (!_isInventoryTrackerSheet()) return;
    _ensureInventoryCommentColumn();

    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    final canEdit = (role == 'admin' || role == 'editor') && !widget.readOnly;

    final row = _data[rowIndex];
    final productKey = _inventoryProductNameKey();
    final commentKey = _inventoryCommentKey();
    final titleKey = _inventoryNoteTitleKey();
    final typeKey = _inventoryNoteTypeKey();

    final productName =
        (productKey == null ? '' : (row[productKey] ?? '')).trim();
    final existingBody = (row[commentKey] ?? '').trim();
    final existingTitle = (row[titleKey] ?? '').trim();
    final existingTypeRaw = (row[typeKey] ?? '').trim();

    final existingTypeNorm = existingTypeRaw.toLowerCase();
    final bool existingHasNote =
        existingBody.isNotEmpty || existingTitle.isNotEmpty;
    final String existingType = existingTypeNorm.isNotEmpty
        ? existingTypeNorm
        : (existingHasNote
            ? _kInventoryNoteTypeDiscrepancy
            : _kInventoryNoteTypeDiscrepancy);
    final bool isCommentNote = existingType == _kInventoryNoteTypeComment;
    final String typeLabel = isCommentNote ? 'Comment' : 'Discrepancy';

    if (!canEdit) {
      final titleLine = existingTitle.isNotEmpty
          ? 'Note — $existingTitle'
          : (productName.isEmpty ? 'Row Note' : 'Row Note — $productName');
      AppModal.show(
        context,
        title: titleLine,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Type: $typeLabel'),
            if (productName.isNotEmpty) Text('Product: $productName'),
            if (existingTitle.isNotEmpty) Text('Title: $existingTitle'),
            const SizedBox(height: 12),
            SelectableText(
              existingBody.isEmpty ? 'No notes for this row.' : existingBody,
            ),
          ],
        ),
      );
      return;
    }

    final titleController = TextEditingController(text: existingTitle);
    final notesController = TextEditingController(text: existingBody);
    String selectedType = existingType;

    final Map<String, String>? result = await showDialog<Map<String, String>>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final bool isComment = selectedType == _kInventoryNoteTypeComment;
            final String dialogTitle = productName.isEmpty
                ? (isComment ? 'Row Comment' : 'Discrepancy Note')
                : (isComment
                    ? 'Row Comment — $productName'
                    : 'Discrepancy Note — $productName');

            InputDecoration deco({required String hint}) => InputDecoration(
                  hintText: hint,
                  hintStyle: TextStyle(color: _textSecondary),
                  filled: true,
                  fillColor: _surfaceAltColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _borderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: AppColors.primaryBlue, width: 1.5),
                  ),
                );

            return AlertDialog(
              backgroundColor: _surfaceColor,
              title: Text(
                dialogTitle,
                style:
                    TextStyle(color: _textPrimary, fontWeight: FontWeight.w800),
              ),
              content: SizedBox(
                width: 560,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedType),
                      initialValue: selectedType,
                      items: const [
                        DropdownMenuItem(
                          value: _kInventoryNoteTypeDiscrepancy,
                          child: Text('Discrepancy'),
                        ),
                        DropdownMenuItem(
                          value: _kInventoryNoteTypeComment,
                          child: Text('Comment'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedType = v);
                      },
                      decoration: deco(hint: 'Type'),
                      dropdownColor: _surfaceColor,
                      style: TextStyle(color: _textPrimary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: titleController,
                      maxLines: 1,
                      decoration: deco(hint: 'Title (optional)'),
                      style: TextStyle(color: _textPrimary),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notesController,
                      maxLines: 6,
                      decoration: deco(
                        hint: isComment
                            ? 'Add a quick comment for this row'
                            : 'Describe the discrepancy (actual count, reason, action taken)',
                      ),
                      style: TextStyle(color: _textPrimary),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(null),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    final title = titleController.text.trim();
                    final body = notesController.text.trim();
                    final type =
                        (title.isEmpty && body.isEmpty) ? '' : selectedType;
                    Navigator.of(ctx).pop({
                      typeKey: type,
                      titleKey: title,
                      commentKey: body,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final newBody = (result[commentKey] ?? '').trim();
    final newTitle = (result[titleKey] ?? '').trim();
    final newType = (result[typeKey] ?? '').trim();

    final changed = newBody != existingBody ||
        newTitle != existingTitle ||
        newType != existingTypeRaw;
    if (!changed) return;

    _pushUndoSnapshot();
    setState(() {
      _data[rowIndex][commentKey] = newBody;
      _data[rowIndex][titleKey] = newTitle;
      _data[rowIndex][typeKey] = newType;
    });
    if (_currentSheet != null) {
      SocketService.instance.cellUpdate(
        _currentSheet!.id,
        rowIndex,
        commentKey,
        newBody,
      );
      SocketService.instance.cellUpdate(
        _currentSheet!.id,
        rowIndex,
        titleKey,
        newTitle,
      );
      SocketService.instance.cellUpdate(
        _currentSheet!.id,
        rowIndex,
        typeKey,
        newType,
      );
    }
    _markDirty();
  }

  List<String> _inventoryMiscCols() => _columns
      .where((c) =>
          c != _inventoryCommentKey() &&
          c != _inventoryNoteTypeKey() &&
          c != _inventoryNoteTitleKey() &&
          !_inventoryFrozenLeft().contains(c) &&
          !_inventoryFrozenRight().contains(c) &&
          !c.startsWith('DATE:') &&
          !_kLegacyInventoryCols.contains(c))
      .toList();

  /// Returns visible dates (all, only this week, or only today + yesterday).
  List<String> _inventoryVisibleDates() {
    final keys = _columns.where((c) => c.startsWith('DATE:')).toList()..sort();
    final dates = <String>{};
    for (final k in keys) {
      final parts = k.split(':');
      if (parts.length == 3) dates.add(parts[1]);
    }
    final sorted = dates.toList()..sort();
    if (_inventoryFilterToday) {
      final now = DateTime.now();
      final yesterdayStr =
          _inventoryDateStr(now.subtract(const Duration(days: 1)));
      final todayStr = _inventoryDateStr(now);

      // Keep stable ordering: yesterday then today.
      return [
        if (sorted.contains(yesterdayStr)) yesterdayStr,
        if (sorted.contains(todayStr)) todayStr,
      ];
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

  List<String> _inventoryAllDates() {
    final keys = _columns.where((c) => c.startsWith('DATE:')).toList()..sort();
    final dates = <String>{};
    for (final k in keys) {
      final parts = k.split(':');
      if (parts.length == 3) dates.add(parts[1]);
    }
    final sorted = dates.toList()..sort();
    return sorted;
  }

  bool _inventoryDateHasAnyVisibleSubcolumns(String dateStr) {
    final inKey = 'DATE:$dateStr:IN';
    final outKey = 'DATE:$dateStr:OUT';
    final inIdx = _columns.indexOf(inKey);
    final outIdx = _columns.indexOf(outKey);
    final inVisible = inIdx >= 0 && !_isColumnHidden(inIdx);
    final outVisible = outIdx >= 0 && !_isColumnHidden(outIdx);
    return inVisible || outVisible;
  }

  bool _inventoryDateHasAnyHiddenSubcolumns(String dateStr) {
    final inKey = 'DATE:$dateStr:IN';
    final outKey = 'DATE:$dateStr:OUT';
    final inIdx = _columns.indexOf(inKey);
    final outIdx = _columns.indexOf(outKey);
    final inHidden = inIdx >= 0 && _isColumnHidden(inIdx);
    final outHidden = outIdx >= 0 && _isColumnHidden(outIdx);
    return inHidden || outHidden;
  }

  void _hideInventoryDates(Iterable<String> dateStrs) {
    if (!_isInventoryTrackerSheet()) return;

    final colIndexes = <int>{};
    for (final dateStr in dateStrs) {
      final inIdx = _columns.indexOf('DATE:$dateStr:IN');
      final outIdx = _columns.indexOf('DATE:$dateStr:OUT');
      if (inIdx >= 0) colIndexes.add(inIdx);
      if (outIdx >= 0) colIndexes.add(outIdx);
    }
    if (colIndexes.isEmpty) return;

    _pushUndoSnapshot();
    setState(() {
      _hiddenColumns.addAll(colIndexes);
      _clearSelection();
    });
    _invalidateInventoryColumnCache();
    _markDirty();
  }

  void _unhideInventoryDates(Iterable<String> dateStrs) {
    if (!_isInventoryTrackerSheet()) return;

    final colIndexes = <int>{};
    for (final dateStr in dateStrs) {
      final inIdx = _columns.indexOf('DATE:$dateStr:IN');
      final outIdx = _columns.indexOf('DATE:$dateStr:OUT');
      if (inIdx >= 0) colIndexes.add(inIdx);
      if (outIdx >= 0) colIndexes.add(outIdx);
    }
    if (colIndexes.isEmpty) return;

    _pushUndoSnapshot();
    setState(() {
      _hiddenColumns.removeAll(colIndexes);
      _clearSelection();
    });
    _invalidateInventoryColumnCache();
    _markDirty();
  }

  Future<void> _showInventoryHideDatesDialog() async {
    if (!_isInventoryTrackerSheet()) return;

    final allDates = _inventoryAllDates();
    final candidates =
        allDates.where(_inventoryDateHasAnyVisibleSubcolumns).toList();

    if (candidates.isEmpty) {
      AppModal.showText(
        context,
        title: 'Hide Dates',
        message: allDates.isEmpty
            ? 'No date columns found in this template.'
            : 'All date columns are already hidden.',
      );
      return;
    }

    final selected = <String>{};
    bool selectAll = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void syncSelectAll() {
            selectAll = selected.length == candidates.length;
          }

          void toggleSelectAll(bool v) {
            setDialogState(() {
              selectAll = v;
              selected
                ..clear()
                ..addAll(v ? candidates : const <String>[]);
            });
          }

          return AlertDialog(
            backgroundColor: _surfaceColor,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _borderColor),
            ),
            title: Text(
              'Hide Dates',
              style:
                  TextStyle(color: _textPrimary, fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selectAll,
                    title: Text(
                      'Select all dates',
                      style: TextStyle(color: _textPrimary),
                    ),
                    onChanged: (v) => toggleSelectAll(v == true),
                  ),
                  Divider(height: 1, color: _borderColor),
                  SizedBox(
                    height: 320,
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, i) {
                        final dateStr = candidates[i];
                        final isChecked = selected.contains(dateStr);
                        final label = _inventoryDateLabel(dateStr);
                        return CheckboxListTile(
                          dense: true,
                          value: isChecked,
                          title: Text(
                            '$label ($dateStr)',
                            style: TextStyle(color: _textPrimary),
                          ),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(dateStr);
                              } else {
                                selected.remove(dateStr);
                              }
                              syncSelectAll();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _hideInventoryDates(allDates);
                },
                child: const Text('Hide All'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        _hideInventoryDates(selected);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Hide Selected'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showInventoryUnhideDatesDialog() async {
    if (!_isInventoryTrackerSheet()) return;

    final allDates = _inventoryAllDates();
    final candidates =
        allDates.where(_inventoryDateHasAnyHiddenSubcolumns).toList();

    if (candidates.isEmpty) {
      AppModal.showText(
        context,
        title: 'Unhide Dates',
        message: allDates.isEmpty
            ? 'No date columns found in this template.'
            : 'No hidden date columns to unhide.',
      );
      return;
    }

    final selected = <String>{};
    bool selectAll = false;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void syncSelectAll() {
            selectAll = selected.length == candidates.length;
          }

          void toggleSelectAll(bool v) {
            setDialogState(() {
              selectAll = v;
              selected
                ..clear()
                ..addAll(v ? candidates : const <String>[]);
            });
          }

          return AlertDialog(
            backgroundColor: _surfaceColor,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: _borderColor),
            ),
            title: Text(
              'Unhide Dates',
              style:
                  TextStyle(color: _textPrimary, fontWeight: FontWeight.w800),
            ),
            content: SizedBox(
              width: 460,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: selectAll,
                    title: Text(
                      'Select all dates',
                      style: TextStyle(color: _textPrimary),
                    ),
                    onChanged: (v) => toggleSelectAll(v == true),
                  ),
                  Divider(height: 1, color: _borderColor),
                  SizedBox(
                    height: 320,
                    child: ListView.builder(
                      itemCount: candidates.length,
                      itemBuilder: (context, i) {
                        final dateStr = candidates[i];
                        final isChecked = selected.contains(dateStr);
                        final label = _inventoryDateLabel(dateStr);
                        return CheckboxListTile(
                          dense: true,
                          value: isChecked,
                          title: Text(
                            '$label ($dateStr)',
                            style: TextStyle(color: _textPrimary),
                          ),
                          onChanged: (v) {
                            setDialogState(() {
                              if (v == true) {
                                selected.add(dateStr);
                              } else {
                                selected.remove(dateStr);
                              }
                              syncSelectAll();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _unhideInventoryDates(allDates);
                },
                child: const Text('Unhide All'),
              ),
              ElevatedButton(
                onPressed: selected.isEmpty
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        _unhideInventoryDates(selected);
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Unhide Selected'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Actions ──────────────────────────────────────────

  int _inventoryInsertIndexForDate(String dateStr) {
    // Insert before the first later date group (IN column), if any.
    for (int i = 0; i < _columns.length; i++) {
      final c = _columns[i];
      if (c.startsWith('DATE:') && c.endsWith(':IN')) {
        final parts = c.split(':');
        if (parts.length == 3) {
          final d = parts[1];
          if (d.compareTo(dateStr) > 0) return i;
        }
      }
    }

    // Otherwise insert just before Total Quantity, or at the end.
    final totalKey = _inventoryTotalQtyKey();
    final totalIdx = totalKey == null ? -1 : _columns.indexOf(totalKey);
    return totalIdx >= 0 ? totalIdx : _columns.length;
  }

  /// Silently injects today's and yesterday's date columns if missing.
  /// Called automatically on sheet open (admin / editor only).
  void _autoInjectTodayColumnIfNeeded() {
    if (!_isInventoryTrackerSheet()) return;
    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    if (role != 'admin' && role != 'editor') return;

    final now = DateTime.now();
    final yesterdayStr =
        _inventoryDateStr(now.subtract(const Duration(days: 1)));
    final todayStr = _inventoryDateStr(now);
    final yesterdayInKey = 'DATE:$yesterdayStr:IN';
    final todayInKey = 'DATE:$todayStr:IN';

    final hasLegacyStatic = _columns.contains('Date') ||
        _columns.contains('IN') ||
        _columns.contains('OUT');
    final needsYesterday = !_columns.contains(yesterdayInKey);
    final needsToday = !_columns.contains(todayInKey);
    if (!hasLegacyStatic && !needsYesterday && !needsToday) return;

    setState(() {
      for (final old in ['Date', 'IN', 'OUT']) {
        _columns.remove(old);
        for (final row in _data) {
          row.remove(old);
        }
      }

      void insertPair(String dateStr) {
        final inKey = 'DATE:$dateStr:IN';
        final outKey = 'DATE:$dateStr:OUT';
        if (_columns.contains(inKey)) return;

        final insertAt = _inventoryInsertIndexForDate(dateStr);
        _columns.insert(insertAt, inKey);
        _columns.insert(insertAt + 1, outKey);

        for (final row in _data) {
          row.putIfAbsent(inKey, () => '');
          row.putIfAbsent(outKey, () => '');
        }
      }

      // Keep ordering: yesterday then today.
      insertPair(yesterdayStr);
      insertPair(todayStr);

      _hasUnsavedChanges = true;
      _saveStatus = 'unsaved';
    });

    _invalidateInventoryColumnCache();

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
      AppModal.showText(
        context,
        title: 'Notice',
        message: 'A column for $dateStr already exists.',
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
      // Insert the new date pair in chronological order (or before Total Quantity).
      final insertAt = _inventoryInsertIndexForDate(dateStr);
      _columns.insert(insertAt, inKey);
      _columns.insert(insertAt + 1, outKey);
      for (final row in _data) {
        row.putIfAbsent(inKey, () => '');
        row.putIfAbsent(outKey, () => '');
      }
      _hasUnsavedChanges = true;
      _saveStatus = 'unsaved';
    });

    _invalidateInventoryColumnCache();

    _recalcInventoryTotals();
    _saveSheet();
  }

  void _scrollToInventoryToday() {
    final now = DateTime.now();
    final yesterdayStr =
        _inventoryDateStr(now.subtract(const Duration(days: 1)));
    final todayStr = _inventoryDateStr(now);
    final inKey = 'DATE:$todayStr:IN';

    if (!_columns.contains(inKey)) {
      AppModal.showText(
        context,
        title: 'Notice',
        message:
            'No column for today ($todayStr). Use "Add Date Column" first.',
      );
      return;
    }

    // Toggle: if already showing only today, go back to all dates.
    if (_inventoryFilterToday) {
      setState(() {
        _inventoryFilterToday = false;
      });
      _invalidateInventoryColumnCache();
      return;
    }

    // Filter to today + yesterday and turn off week filter.
    setState(() {
      _inventoryFilterToday = true;
      _inventoryFilterWeek = false;
    });
    _invalidateInventoryColumnCache();

    // Scroll to today's column after layout settles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      double colWidthForKey(String colKey) {
        final colIdx = _columns.indexOf(colKey);
        final base = colKey.startsWith('DATE:') ? _invSubColW : _invFixedColW;
        if (colIdx < 0) return base;
        return _columnWidths[colIdx] ?? base;
      }

      double offset = _rowNumWidth;
      for (final k in _inventoryFrozenLeft()) {
        final idx = _columns.indexOf(k);
        if (idx >= 0 && !_isColumnHidden(idx)) {
          offset += colWidthForKey(k);
        }
      }

      // In the Today filter, yesterday may be visible before today.
      for (final d in [yesterdayStr]) {
        final yIn = 'DATE:$d:IN';
        final yOut = 'DATE:$d:OUT';
        final inIdx = _columns.indexOf(yIn);
        final outIdx = _columns.indexOf(yOut);
        if (inIdx >= 0 && !_isColumnHidden(inIdx)) {
          offset += colWidthForKey(yIn);
        }
        if (outIdx >= 0 && !_isColumnHidden(outIdx)) {
          offset += colWidthForKey(yOut);
        }
      }

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
    _inventoryStockCountsDirty = true;
    setState(() {
      for (final row in _data) {
        final productKey = _inventoryProductNameKey();
        final stockKey = _inventoryStockKey();
        final totalKey = _inventoryTotalQtyKey();

        final productName =
            (productKey == null ? '' : (row[productKey] ?? '')).trim();
        final code = _inventoryRowCode(row).trim();
        if (productName.isEmpty && code.isEmpty) {
          if (stockKey != null && row.containsKey(stockKey)) row[stockKey] = '';
          if (totalKey != null && row.containsKey(totalKey)) row[totalKey] = '';
          continue;
        }

        String readCell(String? k) {
          if (k == null) return '';
          return (row[k] ?? '').toString().trim();
        }

        var totalIn = 0;
        var totalOut = 0;
        var hasAnyDateEntry = false;
        for (final col in _columns) {
          if (!col.startsWith('DATE:')) continue;
          final v = (row[col] ?? '').toString().trim();
          if (v.isNotEmpty) hasAnyDateEntry = true;

          if (col.endsWith(':IN')) {
            totalIn += int.tryParse(v.isEmpty ? '0' : v) ?? 0;
          } else if (col.endsWith(':OUT')) {
            totalOut += int.tryParse(v.isEmpty ? '0' : v) ?? 0;
          }
        }

        // Base stock should come from the Stock column.
        // Never use Total Quantity as the running base when date entries exist,
        // otherwise totals will compound on every recalculation.
        // If Stock is blank but Total Quantity exists, seed Stock once from Total
        // Quantity to establish a stable baseline.
        final stockRaw = readCell(stockKey);
        final totalRaw = readCell(totalKey);

        if (hasAnyDateEntry &&
          stockKey != null &&
          row.containsKey(stockKey) &&
          stockRaw.isEmpty &&
          totalRaw.isNotEmpty) {
          row[stockKey] = totalRaw;
        }

        final seededStockRaw = readCell(stockKey);
        final baseRaw =
          seededStockRaw.isNotEmpty ? seededStockRaw : (!hasAnyDateEntry ? totalRaw : '');
        final base = int.tryParse(baseRaw.isEmpty ? '0' : baseRaw) ?? 0;

        // If there's no base stock and no date entries, treat as "no data".
        if (baseRaw.isEmpty && !hasAnyDateEntry) {
          if (stockKey != null && row.containsKey(stockKey)) row[stockKey] = '';
          if (totalKey != null && row.containsKey(totalKey)) row[totalKey] = '';
          continue;
        }

        // Legacy convenience: if Total Quantity has a value but Stock is blank
        // and there are no date entries, seed Stock from Total Quantity.
        if (!hasAnyDateEntry &&
            stockKey != null &&
            row.containsKey(stockKey) &&
            stockRaw.isEmpty &&
            baseRaw.isNotEmpty) {
          row[stockKey] = baseRaw;
        }

        final currentStock = base + totalIn - totalOut;
        if (totalKey != null && row.containsKey(totalKey)) {
          row[totalKey] = currentStock.toString();
        }
      }
    });
  }

  bool _isInventoryTotalsInputColumn(String colName) {
    if (colName.startsWith('DATE:')) return true;

    final productKey = _inventoryProductNameKey();
    final codeKey = _inventoryCodeKey();
    final stockKey = _inventoryStockKey();
    final totalKey = _inventoryTotalQtyKey();
    return colName == productKey ||
        colName == codeKey ||
        colName == stockKey ||
        colName == totalKey;
  }

  void _recalcInventoryTotalsForRow(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _data.length) return;
    _inventoryStockCountsDirty = true;
    final row = _data[rowIndex];
    final productKey = _inventoryProductNameKey();
    final stockKey = _inventoryStockKey();
    final totalKey = _inventoryTotalQtyKey();
    final productName =
        (productKey == null ? '' : (row[productKey] ?? '')).trim();
    final code = _inventoryRowCode(row).trim();
    if (productName.isEmpty && code.isEmpty) {
      final updates = <String, String>{};
      if (stockKey != null &&
          row.containsKey(stockKey) &&
          (row[stockKey] ?? '') != '') {
        updates[stockKey] = '';
      }
      if (totalKey != null &&
          row.containsKey(totalKey) &&
          (row[totalKey] ?? '') != '') {
        updates[totalKey] = '';
      }
      if (updates.isNotEmpty) {
        setState(() {
          updates.forEach((k, v) => row[k] = v);
        });
      }
      return;
    }

    String readCell(String? k) {
      if (k == null) return '';
      return (row[k] ?? '').toString().trim();
    }

    var totalIn = 0;
    var totalOut = 0;
    var hasAnyDateEntry = false;
    for (final col in _columns) {
      if (!col.startsWith('DATE:')) continue;
      final v = (row[col] ?? '').toString().trim();
      if (v.isNotEmpty) hasAnyDateEntry = true;

      if (col.endsWith(':IN')) {
        totalIn += int.tryParse(v.isEmpty ? '0' : v) ?? 0;
      } else if (col.endsWith(':OUT')) {
        totalOut += int.tryParse(v.isEmpty ? '0' : v) ?? 0;
      }
    }

    final stockRaw = readCell(stockKey);
    final totalRaw = readCell(totalKey);
    final updates = <String, String>{};

    // If date entries exist but Stock is blank and Total Quantity exists, seed Stock
    // once from Total Quantity to establish a stable baseline.
    var effectiveStockRaw = stockRaw;
    if (hasAnyDateEntry &&
        stockKey != null &&
        row.containsKey(stockKey) &&
        effectiveStockRaw.isEmpty &&
        totalRaw.isNotEmpty) {
      effectiveStockRaw = totalRaw;
      if ((row[stockKey] ?? '') != totalRaw) {
        updates[stockKey] = totalRaw;
      }
    }

    final baseRaw = effectiveStockRaw.isNotEmpty
        ? effectiveStockRaw
        : (!hasAnyDateEntry ? totalRaw : '');
    final base = int.tryParse(baseRaw.isEmpty ? '0' : baseRaw) ?? 0;

    if (baseRaw.isEmpty && !hasAnyDateEntry) {
      if (stockKey != null &&
          row.containsKey(stockKey) &&
          (row[stockKey] ?? '') != '') {
        updates[stockKey] = '';
      }
      if (totalKey != null &&
          row.containsKey(totalKey) &&
          (row[totalKey] ?? '') != '') {
        updates[totalKey] = '';
      }
      if (updates.isNotEmpty) {
        setState(() {
          updates.forEach((k, v) => row[k] = v);
        });
      }
      return;
    }

    if (!hasAnyDateEntry &&
        stockKey != null &&
        row.containsKey(stockKey) &&
        stockRaw.isEmpty &&
        baseRaw.isNotEmpty &&
        (row[stockKey] ?? '') != baseRaw) {
      updates[stockKey] = baseRaw;
    }

    final currentStock = base + totalIn - totalOut;
    final currentStockStr = currentStock.toString();
    if (totalKey != null &&
        row.containsKey(totalKey) &&
        (row[totalKey] ?? '') != currentStockStr) {
      updates[totalKey] = currentStockStr;
    }

    if (updates.isNotEmpty) {
      setState(() {
        updates.forEach((k, v) => row[k] = v);
      });
    }
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

    _maybeShowInvalidInventoryAmountDialog(
        rowIndex: rowIndex, colName: colName);
    _spreadsheetFocusNode.requestFocus();
  }

  void _maybeShowInvalidInventoryAmountDialog({
    required int rowIndex,
    required String colName,
  }) {
    if (!mounted) return;
    if (_invalidInventoryDialogOpen) return;
    final key = '$rowIndex|$colName';
    if (_lastInvalidInventoryDialogKey == key) return;
    _lastInvalidInventoryDialogKey = key;
    unawaited(_showInvalidInventoryAmountDialog());
  }

  bool _isInventoryRowIdentityEmpty(Map<String, String> row) {
    final productKey = _inventoryProductNameKey();
    final productName =
        (productKey == null ? '' : (row[productKey] ?? '')).trim();
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
    if (!_isInventoryDateQtyEditInvalid(
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

  bool _isInventoryInEditInvalid({
    required int rowIndex,
    required String colName,
    required String proposedValueRaw,
  }) {
    if (!_isInventoryTrackerSheet()) return false;
    if (!colName.startsWith('DATE:') || !colName.endsWith(':IN')) return false;
    if (rowIndex < 0 || rowIndex >= _data.length) return false;

    final row = _data[rowIndex];
    if (_isInventoryRowIdentityEmpty(row)) return false;

    final proposedTrimmed = proposedValueRaw.trim();
    final proposedIn =
        int.tryParse(proposedTrimmed.isEmpty ? '0' : proposedTrimmed);
    return proposedIn == null || proposedIn < 0;
  }

  bool _isInventoryDateQtyEditInvalid({
    required int rowIndex,
    required String colName,
    required String proposedValueRaw,
  }) {
    return _isInventoryOutEditInvalid(
          rowIndex: rowIndex,
          colName: colName,
          proposedValueRaw: proposedValueRaw,
        ) ||
        _isInventoryInEditInvalid(
          rowIndex: rowIndex,
          colName: colName,
          proposedValueRaw: proposedValueRaw,
        );
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

    final stockKey = _inventoryStockKey();
    final totalKey = _inventoryTotalQtyKey();
    final stockRaw = (stockKey == null ? '' : (row[stockKey] ?? '')).trim();
    final totalRaw = (totalKey == null ? '' : (row[totalKey] ?? '')).trim();

    int baseStock() {
      // If Stock is blank but Total Quantity exists, treat Total Quantity as the
      // baseline input (common in older sheets that didn't keep Stock updated).
      final baseRaw = stockRaw.isNotEmpty
          ? stockRaw
          : (totalRaw.isNotEmpty ? totalRaw : '');
      return int.tryParse(baseRaw.isEmpty ? '0' : baseRaw) ?? 0;
    }

    final totalsBefore = _inventoryTotalsForRow(row);
    final totalsAfter = _inventoryTotalsForRow(
      row,
      overrideOutCol: colName,
      overrideOutValue: proposedOut,
    );

    final currentOut = _parseInventoryQtyOrZero(row[colName]);
    final beforeTotal =
      baseStock() + (totalsBefore['net'] ?? 0);
    final afterTotal =
      baseStock() + (totalsAfter['net'] ?? 0);

    if (afterTotal >= 0) return false;

    // Allow the user to "fix" an already-invalid row by reducing OUT.
    final isReducingOut = proposedOut <= currentOut;
    if (beforeTotal < 0 && isReducingOut && afterTotal >= beforeTotal) {
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
            'Invalid amount. Only whole numbers are allowed. IN/OUT must be 0 or more, and OUT cannot make total quantity negative. Value is set to 0.',
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
              _invalidateInventoryColumnCache();
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
                    hintText: 'Search Material Name or QB Code…',
                    hintStyle:
                        const TextStyle(fontSize: 13, color: Color(0xFFAAAAAA)),
                    prefixIcon: const Icon(Icons.search,
                        size: 18, color: AppColors.primaryBlue),
                    suffixIcon: _inventorySearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                size: 16, color: Color(0xFF888888)),
                            onPressed: () {
                              setState(() {
                                _inventorySearchQuery = '';
                                _inventorySearchController.clear();
                              });
                              _invalidateInventoryRowCache();
                            },
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
                  onChanged: (v) {
                    setState(() => _inventorySearchQuery = v.trim());
                    _invalidateInventoryRowCache();
                  },
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
                  final productKey = _inventoryProductNameKey();
                  return (productKey == null ? '' : (row[productKey] ?? ''))
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportHeight = constraints.maxHeight;
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
                        child: _buildInventoryGridContent(
                            viewportHeight: viewportHeight),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildInventoryGridContent({required double viewportHeight}) {
    final frozenLeft = _inventoryFrozenLeft();
    final frozenRight = _inventoryFrozenRight();
    final miscCols = _inventoryMiscCols();
    final visibleDates = _inventoryVisibleDates();

    final role =
        Provider.of<AuthProvider>(context, listen: false).user?.role ?? '';
    final isAdminOrEditor = role == 'admin' || role == 'editor';
    final isViewer = role == 'viewer';
    final todayStr = _inventoryDateStr(DateTime.now());

    _ensureInventoryRowCache();

    // Only rebuild the column cache (visible columns + prefix widths) when a
    // relevant change happens (hide/unhide, add/delete columns, resize, date
    // filters). This prevents repeated work on unrelated setState rebuilds.
    if (_inventoryColumnCacheDirty ||
        _inventoryCachedColIndexByKey.length != _columns.length) {
      _inventoryCachedColIndexByKey
        ..clear()
        ..addEntries(
            _columns.asMap().entries.map((e) => MapEntry(e.value, e.key)));

      double colWidthForKey(String colKey) {
        final colIdx = _inventoryCachedColIndexByKey[colKey] ?? -1;
        final base = colKey.startsWith('DATE:') ? _invSubColW : _invFixedColW;
        if (colIdx < 0) return base;
        return _columnWidths[colIdx] ?? base;
      }

      final visibleColumnKeys = <String>[];
      for (final key in frozenLeft) {
        final idx = _inventoryCachedColIndexByKey[key] ?? -1;
        if (idx >= 0 && !_isColumnHidden(idx)) visibleColumnKeys.add(key);
      }
      for (final date in visibleDates) {
        final inKey = 'DATE:$date:IN';
        final outKey = 'DATE:$date:OUT';
        final inIdx = _inventoryCachedColIndexByKey[inKey] ?? -1;
        final outIdx = _inventoryCachedColIndexByKey[outKey] ?? -1;
        if (inIdx >= 0 && !_isColumnHidden(inIdx)) visibleColumnKeys.add(inKey);
        if (outIdx >= 0 && !_isColumnHidden(outIdx)) {
          visibleColumnKeys.add(outKey);
        }
      }
      for (final key in miscCols) {
        final idx = _inventoryCachedColIndexByKey[key] ?? -1;
        if (idx >= 0 && !_isColumnHidden(idx)) visibleColumnKeys.add(key);
      }
      for (final key in frozenRight) {
        final idx = _inventoryCachedColIndexByKey[key] ?? -1;
        if (idx >= 0 && !_isColumnHidden(idx)) visibleColumnKeys.add(key);
      }

      // Cache visible columns + prefix widths (used by hit-testing and drag
      // selection). This build does not run on scroll, so it's safe to do here.
      final colPrefix = <double>[0.0];
      for (final colKey in visibleColumnKeys) {
        colPrefix.add(colPrefix.last + colWidthForKey(colKey));
      }
      _inventoryCachedVisibleColumnKeys = visibleColumnKeys;
      _inventoryCachedColPrefixWidths = colPrefix;
      _inventoryCachedTotalWidth =
          _rowNumWidth + (colPrefix.isEmpty ? 0.0 : colPrefix.last);
      _inventoryColumnCacheDirty = false;
    }

    Map<String, int>? inventoryCellFromPosition(Offset localPosition) {
      final x = localPosition.dx / _zoomLevel;
      final y = localPosition.dy / _zoomLevel;
      final dataStartY = _invHeaderH1 + _invHeaderH2;

      if (x < _rowNumWidth || y < dataStartY) return null;

      final entries = _inventoryCachedEntries;
      final prefix = _inventoryCachedRowPrefixHeights;
      final n = entries.length;
      if (n == 0 || prefix.length != n + 1) return null;

      // Resolve row using prefix-sums (O(log n)).
      final yInData = y - dataStartY;
      if (yInData < 0) return null;
      final rowPos = _upperBoundDouble(prefix, yInData) - 1;
      if (rowPos < 0 || rowPos >= n) return null;
      final resolvedRow = entries[rowPos].key;

      // Resolve column using prefix-sums (O(log m)).
      final xInData = x - _rowNumWidth;
      if (xInData < 0) return null;
      final colKeys = _inventoryCachedVisibleColumnKeys;
      final colPx = _inventoryCachedColPrefixWidths;
      final m = colKeys.length;
      if (m == 0 || colPx.length != m + 1) return null;
      final colPos = _upperBoundDouble(colPx, xInData) - 1;
      if (colPos < 0 || colPos >= m) return null;
      final colKey = colKeys[colPos];
      final col = _inventoryCachedColIndexByKey[colKey] ?? -1;
      if (col < 0) return null;
      return {'row': resolvedRow, 'col': col};
    }

    final dataStartY = _invHeaderH1 + _invHeaderH2;
    final dataRowsHeight = _inventoryCachedDataRowsHeight;
    final totalWidth = _inventoryCachedTotalWidth;
    final double totalHeight = dataStartY + dataRowsHeight + 16;

    final header = _buildInventoryHeaderRows(
      frozenLeft,
      frozenRight,
      miscCols,
      visibleDates,
      canDelete: isAdminOrEditor && !widget.readOnly,
    );

    final gridContent = SizedBox(
      width: totalWidth,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          AnimatedBuilder(
            animation: _verticalScrollController,
            builder: (context, _) {
              final entries = _inventoryCachedEntries;
              final prefix = _inventoryCachedRowPrefixHeights;
              final n = entries.length;
              if (n == 0 || prefix.length != n + 1) {
                return const SizedBox.shrink();
              }

              final scrollOffset = _verticalScrollController.hasClients
                  ? _verticalScrollController.offset
                  : 0.0;
              final yUnscaled = scrollOffset / _zoomLevel;
              final viewportUnscaled = viewportHeight / _zoomLevel;

              final viewTop = (yUnscaled - dataStartY)
                  .clamp(0.0, dataRowsHeight.toDouble());
              final viewBottom = (viewTop + viewportUnscaled)
                  .clamp(0.0, dataRowsHeight.toDouble());

              final overscan = (viewportUnscaled * 0.6).clamp(240.0, 900.0);
              final startOffset =
                  (viewTop - overscan).clamp(0.0, dataRowsHeight.toDouble());
              final endOffset =
                  (viewBottom + overscan).clamp(0.0, dataRowsHeight.toDouble());

              final start =
                  (_upperBoundDouble(prefix, startOffset) - 1).clamp(0, n);
              final end = _lowerBoundDouble(prefix, endOffset).clamp(start, n);

              final topSpacer = prefix[start].clamp(0.0, dataRowsHeight);
              final bottomSpacer =
                  (dataRowsHeight - prefix[end]).clamp(0.0, dataRowsHeight);

              final widgets = <Widget>[];
              if (topSpacer > 0) {
                widgets.add(SizedBox(height: topSpacer.toDouble()));
              }
              for (int i = start; i < end; i++) {
                widgets.add(_buildInventoryDataRow(
                  entries[i].key,
                  frozenLeft,
                  frozenRight,
                  miscCols,
                  visibleDates,
                  isAdminOrEditor: isAdminOrEditor && !widget.readOnly,
                  isViewer: isViewer,
                  todayStr: todayStr,
                  displayRowNumber: i + 3,
                ));
              }
              if (bottomSpacer > 0) {
                widgets.add(SizedBox(height: bottomSpacer.toDouble()));
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: widgets,
              );
            },
          ),
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

  List<MapEntry<int, Map<String, String>>> _inventoryFilteredEntries() {
    final productKey = _inventoryProductNameKey();
    final q = _inventorySearchQuery.toLowerCase();

    final List<MapEntry<int, Map<String, String>>> filteredEntries = (q.isEmpty
            ? _data.asMap().entries
            : _data.asMap().entries.where((e) {
                final row = e.value;
                return (productKey == null ? '' : (row[productKey] ?? ''))
                        .toString()
                        .toLowerCase()
                        .contains(q) ||
                    _inventoryRowCode(row).toString().toLowerCase().contains(q);
              }))
        .where((e) => !_isRowHidden(e.key))
        .toList();

    String norm(String v) => v.trim().toLowerCase();
    String nameKey(Map<String, String> row) {
      final n =
          norm((productKey == null ? '' : (row[productKey] ?? '')).toString());
      return n.isEmpty ? '\u{10FFFF}' : n;
    }

    String codeKey(Map<String, String> row) {
      final c = norm(_inventoryRowCode(row).toString());
      return c.isEmpty ? '\u{10FFFF}' : c;
    }

    // Sorting can be expensive on large Inventory sheets because the comparator
    // runs many times. Cache derived keys per row index so we don't repeatedly
    // normalize/scan within the comparator.
    final nameCache = <int, String>{};
    final codeCache = <int, String>{};
    final lowStockCache = <int, double>{};
    final discrepancyCache = <int, bool>{};

    String entryName(MapEntry<int, Map<String, String>> e) =>
        nameCache.putIfAbsent(e.key, () => nameKey(e.value));
    String entryCode(MapEntry<int, Map<String, String>> e) =>
        codeCache.putIfAbsent(e.key, () => codeKey(e.value));
    double entryLowStock(MapEntry<int, Map<String, String>> e) => lowStockCache
        .putIfAbsent(e.key, () => _inventoryLowStockScoreForRow(e.value));
    bool entryHasDiscrepancy(MapEntry<int, Map<String, String>> e) =>
        discrepancyCache.putIfAbsent(
            e.key, () => _inventoryRowHasDiscrepancy(e.value));

    filteredEntries.sort((a, b) {
      switch (_inventorySortMode) {
        case _InventorySortMode.normal:
          return a.key.compareTo(b.key);
        case _InventorySortMode.nameAsc:
          final c1 = entryName(a).compareTo(entryName(b));
          if (c1 != 0) return c1;
          return entryCode(a).compareTo(entryCode(b));
        case _InventorySortMode.codeAsc:
          final c1 = entryCode(a).compareTo(entryCode(b));
          if (c1 != 0) return c1;
          return entryName(a).compareTo(entryName(b));
        case _InventorySortMode.lowStockFirst:
          final da = entryLowStock(a);
          final db = entryLowStock(b);
          final c1 = db.compareTo(da); // higher severity first
          if (c1 != 0) return c1;
          final c2 = entryName(a).compareTo(entryName(b));
          if (c2 != 0) return c2;
          return entryCode(a).compareTo(entryCode(b));
        case _InventorySortMode.discrepancyFirst:
          final aDisc = entryHasDiscrepancy(a) ? 0 : 1;
          final bDisc = entryHasDiscrepancy(b) ? 0 : 1;
          final c0 = aDisc.compareTo(bDisc);
          if (c0 != 0) return c0;
          final c1 = entryName(a).compareTo(entryName(b));
          if (c1 != 0) return c1;
          return entryCode(a).compareTo(entryCode(b));
      }
    });

    return filteredEntries;
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

    int colIndexForKey(String colKey) {
      final cached = _inventoryCachedColIndexByKey[colKey];
      if (cached != null) return cached;
      return _columns.indexOf(colKey);
    }

    double colWidthForKey(String colKey) {
      final colIdx = colIndexForKey(colKey);
      final base = colKey.startsWith('DATE:') ? _invSubColW : _invFixedColW;
      if (colIdx < 0) return base;
      return _columnWidths[colIdx] ?? base;
    }

    BoxDecoration deco(Color bg) => BoxDecoration(
          color: bg,
          border: const Border(
            right: BorderSide(color: borderCol, width: 1),
            bottom: BorderSide(color: borderCol, width: 1),
          ),
        );

    final double fullHeaderH = _invHeaderH1 + _invHeaderH2;

    Widget resizableHeaderCell({
      required String colKey,
      required String label,
      required double height,
      required Color bg,
      bool bold = true,
    }) {
      final colIndex = colIndexForKey(colKey);
      if (colIndex < 0 || _isColumnHidden(colIndex)) {
        return const SizedBox.shrink();
      }

      final w = colWidthForKey(colKey);

      final adjacentHidden = _findHiddenColumnsNear(colIndex);
      final hasHiddenLeft = adjacentHidden.any((c) => c < colIndex);
      final hasHiddenRight = adjacentHidden.any((c) => c > colIndex);

      return SizedBox(
        width: w,
        height: height,
        child: Stack(
          children: [
            GestureDetector(
              onDoubleTap:
                  _canEditSheet() ? () => _renameColumn(colIndex) : null,
              onSecondaryTapDown: (details) {
                _showColumnHeaderContextMenu(
                    context, details.globalPosition, colIndex);
              },
              child: Container(
                width: w,
                height: height,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: bg,
                  border: Border(
                    right: const BorderSide(color: borderCol, width: 1),
                    bottom: const BorderSide(color: borderCol, width: 1),
                    left: hasHiddenLeft
                        ? const BorderSide(color: Colors.green, width: 2)
                        : BorderSide.none,
                  ),
                ),
                child: Text(
                  colKey == _inventoryCommentKey() ? 'Notes' : label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: bold ? FontWeight.bold : FontWeight.w500,
                    color: textCol,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (details) {
                    if (_canEditSheet()) {
                      _pushUndoSnapshot();
                    }
                    _isResizingColumn = true;
                    _resizingColumnIndex = colIndex;
                    _resizingStartX = details.globalPosition.dx;
                    _resizingStartWidth = w;
                  },
                  onHorizontalDragUpdate: (details) {
                    if (_isResizingColumn && _resizingColumnIndex == colIndex) {
                      final delta =
                          (details.globalPosition.dx - _resizingStartX) /
                              _zoomLevel;
                      final newWidth = (_resizingStartWidth + delta)
                          .clamp(_minCellWidth, 500.0);
                      setState(() {
                        _columnWidths[colIndex] = newWidth;
                      });
                    }
                  },
                  onHorizontalDragEnd: (_) {
                    _isResizingColumn = false;
                    _resizingColumnIndex = null;
                    _markDirty();
                  },
                  child: Container(width: 10, color: Colors.transparent),
                ),
              ),
            ),
            if (hasHiddenRight)
              Positioned(
                right: 0,
                top: 0,
                bottom: 0,
                child: Container(width: 2, color: Colors.green),
              ),
          ],
        ),
      );
    }

    // Date group header with embedded IN/OUT sub-header (no gap).
    Widget dateGroupCell(String date) {
      final isToday = date == todayStr;
      final bg = isToday ? todayCol : midBlue;
      final subBg = isToday ? todaySub : subBlue;
      final label = isToday
          ? '${_inventoryDateLabel(date)}  TODAY'
          : _inventoryDateLabel(date);

      final inKey = 'DATE:$date:IN';
      final outKey = 'DATE:$date:OUT';
      final inIdx = colIndexForKey(inKey);
      final outIdx = colIndexForKey(outKey);

      final bool inVisible = inIdx >= 0 && !_isColumnHidden(inIdx);
      final bool outVisible = outIdx >= 0 && !_isColumnHidden(outIdx);
      if (!inVisible && !outVisible) {
        return const SizedBox.shrink();
      }

      final double inW = inVisible ? colWidthForKey(inKey) : 0.0;
      final double outW = outVisible ? colWidthForKey(outKey) : 0.0;
      final double groupW = inW + outW;

      // Right-clicking the group uses the first visible sub-column.
      final int? groupMenuCol =
          inVisible ? inIdx : (outVisible ? outIdx : null);

      return SizedBox(
        width: groupW,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onSecondaryTapDown: groupMenuCol == null
                  ? null
                  : (details) {
                      _showColumnHeaderContextMenu(
                          context, details.globalPosition, groupMenuCol);
                    },
              child: Container(
                width: groupW,
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
            ),
            Row(
              children: [
                if (inVisible)
                  resizableHeaderCell(
                    colKey: inKey,
                    label: 'IN',
                    height: _invHeaderH2,
                    bg: subBg,
                    bold: false,
                  ),
                if (outVisible)
                  resizableHeaderCell(
                    colKey: outKey,
                    label: 'OUT',
                    height: _invHeaderH2,
                    bg: subBg,
                    bold: false,
                  ),
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
          child: ClipRect(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final headerTotalH = constraints.maxHeight;
                final h1 = _invHeaderH1.clamp(0.0, headerTotalH);
                final h2 = (headerTotalH - h1).clamp(0.0, double.infinity);

                void beginResize(DragStartDetails details,
                    {required bool divider}) {
                  if (_canEditSheet()) {
                    _pushUndoSnapshot();
                  }
                  setState(() {
                    _isResizingInvHeader = true;
                    _isResizingInvHeaderDivider = divider;
                    _invHeaderResizeStartY = details.globalPosition.dy;
                    _invHeaderResizeStartH1 = _invHeaderH1;
                    _invHeaderResizeStartH2 = _invHeaderH2;
                  });
                }

                void updateResize(DragUpdateDetails details) {
                  if (!_isResizingInvHeader) return;
                  final delta =
                      (details.globalPosition.dy - _invHeaderResizeStartY) /
                          _zoomLevel;

                  if (_isResizingInvHeaderDivider) {
                    final total =
                        _invHeaderResizeStartH1 + _invHeaderResizeStartH2;
                    var newH1 = (_invHeaderResizeStartH1 + delta)
                        .clamp(_invMinHeaderRowH, total - _invMinHeaderRowH);
                    var newH2 = total - newH1;
                    // Cap to max while respecting min.
                    if (newH1 > _invMaxHeaderRowH) {
                      newH1 = _invMaxHeaderRowH;
                      newH2 = total - newH1;
                    }
                    if (newH2 > _invMaxHeaderRowH) {
                      newH2 = _invMaxHeaderRowH;
                      newH1 = total - newH2;
                    }
                    newH1 = newH1.clamp(_invMinHeaderRowH, _invMaxHeaderRowH);
                    newH2 = newH2.clamp(_invMinHeaderRowH, _invMaxHeaderRowH);
                    setState(() {
                      _invHeaderH1 = newH1;
                      _invHeaderH2 = newH2;
                    });
                  } else {
                    final newH2 = (_invHeaderResizeStartH2 + delta)
                        .clamp(_invMinHeaderRowH, _invMaxHeaderRowH);
                    setState(() {
                      _invHeaderH2 = newH2;
                    });
                  }
                }

                void endResize([DragEndDetails? _]) {
                  if (!_isResizingInvHeader) return;
                  setState(() {
                    _isResizingInvHeader = false;
                    _isResizingInvHeaderDivider = false;
                  });
                  _markDirty();
                }

                return Stack(
                  children: [
                    Column(
                      mainAxisSize: MainAxisSize.max,
                      children: [
                        Container(
                          height: h1,
                          decoration: const BoxDecoration(
                            border: Border(
                              bottom: BorderSide(color: borderCol, width: 1),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '1',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: h2,
                          child: const Center(
                            child: Text(
                              '2',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    // Divider between header rows (resize row 1 vs row 2)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: (h1 - 5).clamp(0.0, headerTotalH - 10),
                      height: 10,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragStart: (d) =>
                              beginResize(d, divider: true),
                          onVerticalDragUpdate: updateResize,
                          onVerticalDragEnd: endResize,
                          onVerticalDragCancel: () => endResize(),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    // Bottom edge (resize row 2 height)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 10,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.resizeRow,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onVerticalDragStart: (d) =>
                              beginResize(d, divider: false),
                          onVerticalDragUpdate: updateResize,
                          onVerticalDragEnd: endResize,
                          onVerticalDragCancel: () => endResize(),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
        for (final col in frozenLeft)
          resizableHeaderCell(
              colKey: col,
              label: _displayColumnName(col),
              height: fullHeaderH,
              bg: navy,
              bold: true),
        for (final date in visibleDates)
          if ((() {
            final inIdx = colIndexForKey('DATE:$date:IN');
            final outIdx = colIndexForKey('DATE:$date:OUT');
            final inVisible = inIdx >= 0 && !_isColumnHidden(inIdx);
            final outVisible = outIdx >= 0 && !_isColumnHidden(outIdx);
            return inVisible || outVisible;
          })())
            dateGroupCell(date),
        for (final col in miscCols)
          resizableHeaderCell(
              colKey: col,
              label: _displayColumnName(col),
              height: fullHeaderH,
              bg: navy,
              bold: true),
        for (final col in frozenRight)
          resizableHeaderCell(
              colKey: col,
              label: _displayColumnName(col),
              height: fullHeaderH,
              bg: darkNavy,
              bold: true),
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
    int? displayRowNumber,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final row = _data[rowIndex];
    final productKey = _inventoryProductNameKey();
    final stockKey = _inventoryStockKey();
    final totalQtyKey = _inventoryTotalQtyKey();
    final commentKey = _inventoryCommentKey();
    final noteTitleKey = _inventoryNoteTitleKey();
    final noteTypeKey = _inventoryNoteTypeKey();
    final bool isRowSelected = _selectedRow == rowIndex;
    final Color rowBg = _isDark
        ? (rowIndex.isEven
            ? scheme.surface
            : scheme.surfaceContainerHighest.withValues(alpha: 0.55))
        : (rowIndex.isEven ? Colors.white : const Color(0xFFF8F9FA));
    final noteBody = (row[commentKey] ?? '').trim();
    final noteTitle = (row[noteTitleKey] ?? '').trim();
    final noteTypeRaw = (row[noteTypeKey] ?? '').trim();
    final hasNote = noteBody.isNotEmpty || noteTitle.isNotEmpty;
    final noteTypeNorm = noteTypeRaw.toLowerCase();
    final noteType = noteTypeNorm.isNotEmpty
        ? noteTypeNorm
        : (hasNote ? _kInventoryNoteTypeDiscrepancy : '');
    final isCommentNote = noteType == _kInventoryNoteTypeComment;

    final gridBorderColor = _isDark ? scheme.outlineVariant : Colors.grey[300]!;
    final rowNumberBorderColor =
        _isDark ? scheme.outlineVariant : Colors.grey[400]!;
    final discrepancyBorderColor =
        AppColors.primaryOrange.withValues(alpha: _isDark ? 0.85 : 0.75);

    // ── Total Quantity colour logic ──────────────────────────────────────────
    // Critical when Total Quantity <= Critical.
    Color? totalQtyColor() {
      final criticalPct = _criticalDeficitPctForRow(row);
      if (criticalPct != null) return AppColors.primaryOrange;

      final maintainingPct = _maintainingDeficitPctForRow(row);
      if (maintainingPct != null) return const Color(0xFFFFB300);

      // In dark mode, the old dark-blue value is unreadable on dark rows.
      return _isDark ? scheme.onSurface : AppColors.primaryBlue;
    }

    final rowHeight = _getRowHeight(rowIndex);

    double colWidthForKey(String colKey) {
      final colIdx = _columns.indexOf(colKey);
      final base = colKey.startsWith('DATE:') ? _invSubColW : _invFixedColW;
      if (colIdx < 0) return base;
      return _columnWidths[colIdx] ?? base;
    }

    Widget dataCell({
      required String colKey,
      required double width,
      required bool editable,
      bool autoCalc = false,
    }) {
      final colIdx = _inventoryCachedColIndexByKey[colKey] ?? -1;
      if (colIdx < 0 || _isColumnHidden(colIdx)) {
        return const SizedBox.shrink();
      }

      // Skip cells that are covered by merged ranges.
      if (_shouldSkipCell(rowIndex, colIdx)) {
        return const SizedBox.shrink();
      }

      // Merged cell handling (horizontal merges are supported; vertical merges
      // are rendered by skipping covered cells but do not expand row height).
      final mergeBounds = _getMergedCellBounds(rowIndex, colIdx);
      final isMerged = mergeBounds != null;
      double cellWidth = width;
      if (isMerged && _isTopLeftOfMergedRange(rowIndex, colIdx)) {
        cellWidth = 0;
        for (int c = mergeBounds['minCol']!; c <= mergeBounds['maxCol']!; c++) {
          if (_isColumnHidden(c)) continue;
          cellWidth += _getColumnWidth(c);
        }
      }

      final isEditing = _editingRow == rowIndex && _editingCol == colIdx;
      final isActiveCell = _selectedRow == rowIndex && _selectedCol == colIdx;
      final isInSel = colIdx >= 0 && _isInSelection(rowIndex, colIdx);
      final value = row[colKey] ?? '';

      final ck = _cellKey(rowIndex, colIdx);
      final customBorders = _cellBorders[ck];
      final customBg = _cellBackgroundColors[ck];
      final customTextColor = _cellTextColors[ck];
      final fmts = _cellFormats[ck] ?? <String>{};
      final fontSize = _cellFontSizes[ck] ?? 12.0;
      final align = _cellAlignments[ck];
      Alignment cellAlign;
      if (align == TextAlign.center) {
        cellAlign = Alignment.center;
      } else if (align == TextAlign.right) {
        cellAlign = Alignment.centerRight;
      } else if (align == TextAlign.left) {
        cellAlign = Alignment.centerLeft;
      } else {
        cellAlign = Alignment.center;
      }

      // For the Total Quantity cell, derive background + text colours from
      // the Critical column rule.
      final bool isTotalQty = totalQtyKey != null && colKey == totalQtyKey;
      final Color? totalQtyFgColor = isTotalQty ? totalQtyColor() : null;
      final bool isTotalQtyCritical =
          isTotalQty && totalQtyFgColor == AppColors.primaryOrange;
      final Color? totalQtyBgColor = isTotalQtyCritical
          ? (_isDark
              ? AppColors.primaryOrange.withValues(alpha: 0.18)
              : const Color(0xFFFFF3E0))
          : null;

      Color bgColor() {
        if (customBg != null && customBg != Colors.transparent) {
          return customBg;
        }
        if (isEditing) return _isDark ? scheme.surface : Colors.white;
        if (_isDark) {
          if (isActiveCell) return scheme.primary.withValues(alpha: 0.35);
          if (isInSel) return scheme.primary.withValues(alpha: 0.22);
          if (isRowSelected) return scheme.primary.withValues(alpha: 0.18);
        } else {
          if (isActiveCell) return const Color(0xFFBBD3FB);
          if (isInSel) return const Color(0xFFD2E3FC);
          if (isRowSelected) return const Color(0xFFE8F0FE);
        }
        if (totalQtyBgColor != null) return totalQtyBgColor;
        if (hasNote) {
          if (isCommentNote) {
            // Stronger tint in dark mode so it's unmistakable.
            return _kGreen.withValues(alpha: _isDark ? 0.32 : 0.10);
          }
          return AppColors.primaryOrange
              .withValues(alpha: _isDark ? 0.22 : 0.08);
        }
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
          (productKey == null ? '' : (row[productKey] ?? '')).trim().isEmpty &&
              _inventoryRowCode(row).trim().isEmpty;
      final String displayValue;
      if (rowIdentityBlank && (isTotalQty || isDateInOut)) {
        displayValue = '';
      } else if (!rowIdentityBlank && isDateInOut && value.isEmpty) {
        displayValue = '0';
      } else if (!rowIdentityBlank &&
          stockKey != null &&
          colKey == stockKey &&
          value.trim().isEmpty) {
        // If Stock is blank, show Total Quantity so Stock never looks empty
        // when the computed total is present.
        displayValue = (totalQtyKey == null ? '' : (row[totalQtyKey] ?? ''))
            .toString()
            .trim();
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
        onSecondaryTapDown: (details) {
          if (colIdx < 0) return;
          if (_editingRow != null) {
            _saveEdit();
          }
          _selectCell(rowIndex, colIdx);
          _showCellContextMenu(
              context, details.globalPosition, rowIndex, colIdx);
        },
        child: Stack(
          children: [
            Container(
              width: cellWidth,
              height: rowHeight,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bgColor(),
                border: customBorders != null
                    ? Border(
                        top: customBorders['top'] == true
                            ? const BorderSide(color: Colors.black, width: 2)
                            : BorderSide.none,
                        right: customBorders['right'] == true
                            ? const BorderSide(color: Colors.black, width: 2)
                            : BorderSide(
                                color: hasNote && !isCommentNote
                                    ? discrepancyBorderColor
                                    : gridBorderColor,
                                width: 1,
                              ),
                        bottom: customBorders['bottom'] == true
                            ? const BorderSide(color: Colors.black, width: 2)
                            : BorderSide(
                                color: hasNote && !isCommentNote
                                    ? discrepancyBorderColor
                                    : gridBorderColor,
                                width: 1,
                              ),
                        left: customBorders['left'] == true
                            ? const BorderSide(color: Colors.black, width: 2)
                            : BorderSide.none,
                      )
                    : Border(
                        right: BorderSide(
                          color: hasNote && !isCommentNote
                              ? discrepancyBorderColor
                              : gridBorderColor,
                          width: 1,
                        ),
                        bottom: BorderSide(
                          color: hasNote && !isCommentNote
                              ? discrepancyBorderColor
                              : gridBorderColor,
                          width: 1,
                        ),
                      ),
              ),
              child: isEditing
                  ? CallbackShortcuts(
                      bindings: {
                        const SingleActivator(LogicalKeyboardKey.tab): () {
                          _handleEditTab(backwards: false);
                        },
                        const SingleActivator(LogicalKeyboardKey.tab,
                            shift: true): () {
                          _handleEditTab(backwards: true);
                        },
                      },
                      child: TextField(
                        controller: _editController,
                        focusNode: _focusNode,
                        autofocus: true,
                        textAlign: align ?? TextAlign.center,
                        inputFormatters: isDateInOut
                            ? <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ]
                            : null,
                        keyboardType: isDateInOut
                            ? const TextInputType.numberWithOptions(
                                signed: false)
                            : TextInputType.text,
                        style: TextStyle(
                          fontSize: fontSize,
                          color: customTextColor ??
                              (totalQtyFgColor ??
                                  (autoCalc
                                      ? (_isDark
                                          ? scheme.primary
                                          : AppColors.primaryBlue)
                                      : (_isDark
                                          ? scheme.onSurface
                                          : Colors.black87))),
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
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: isDateInOut ? (_) {} : null,
                        onSubmitted: (_) {
                          _saveEdit();
                        },
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 6),
                      child: Align(
                        alignment: cellAlign,
                        child: Text(
                          displayValue,
                          style: TextStyle(
                            fontSize: fontSize,
                            color: customTextColor ??
                                (totalQtyFgColor ??
                                    (autoCalc
                                        ? (_isDark
                                            ? scheme.primary
                                            : AppColors.primaryBlue)
                                        : (_isDark
                                            ? scheme.onSurface
                                            : Colors.black87))),
                            fontWeight: fmts.contains('bold')
                                ? FontWeight.bold
                                : (autoCalc
                                    ? FontWeight.w600
                                    : FontWeight.normal),
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
                          textAlign: align ?? TextAlign.center,
                        ),
                      ),
                    ),
            ),
            if (isActiveCell && !isEditing && colIdx >= 0)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: _isDark ? scheme.primary : AppColors.primaryBlue,
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
                        color: cellOccupant.color.withValues(alpha: 0.15),
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
      SizedBox(
        width: _rowNumWidth,
        height: rowHeight,
        child: Stack(
          children: [
            GestureDetector(
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
              onSecondaryTapDown: (details) {
                _showRowHeaderContextMenu(
                    context, details.globalPosition, rowIndex);
              },
              child: Container(
                width: _rowNumWidth,
                height: rowHeight,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isRowSelected
                      ? (_isDark
                          ? scheme.primaryContainer
                          : const Color(0xFF4472C4))
                      : (_isDark
                          ? scheme.surfaceContainerHighest
                          : const Color(0xFFF5F5F5)),
                  border: Border(
                    right: BorderSide(color: rowNumberBorderColor, width: 1),
                    bottom: BorderSide(color: gridBorderColor, width: 1),
                  ),
                ),
                child: Text(
                  '${displayRowNumber ?? _displayRowNumber(rowIndex)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isRowSelected
                        ? (_isDark ? scheme.onSurface : Colors.white)
                        : (_isDark
                            ? scheme.onSurfaceVariant
                            : Colors.grey[600]),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeRow,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onVerticalDragStart: (details) {
                    if (_canEditSheet()) {
                      _pushUndoSnapshot();
                    }
                    _isResizingRow = true;
                    _resizingRowIndex = rowIndex;
                    _resizingStartY = details.globalPosition.dy;
                    _resizingStartHeight = rowHeight;
                  },
                  onVerticalDragUpdate: (details) {
                    if (_isResizingRow && _resizingRowIndex == rowIndex) {
                      final delta =
                          (details.globalPosition.dy - _resizingStartY) /
                              _zoomLevel;
                      final newHeight = (_resizingStartHeight + delta)
                          .clamp(_minRowHeight, _maxRowHeight);
                      setState(() {
                        _rowHeights[rowIndex] = newHeight;
                      });
                      _invalidateInventoryRowCache(prefixOnly: true);
                    }
                  },
                  onVerticalDragEnd: (_) {
                    _isResizingRow = false;
                    _resizingRowIndex = null;
                    _markDirty();
                  },
                  child: Container(height: 10, color: Colors.transparent),
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    // Frozen left
    for (final col in frozenLeft) {
      final idx = _inventoryCachedColIndexByKey[col] ?? -1;
      if (idx < 0 || _isColumnHidden(idx)) continue;
      cells.add(dataCell(
        colKey: col,
        width: colWidthForKey(col),
        editable: isAdminOrEditor &&
            col != _kInventoryCommentCol &&
            col != _kInventoryNoteTypeCol &&
            col != _kInventoryNoteTitleCol,
      ));
    }

    // Date IN/OUT pairs
    for (final date in visibleDates) {
      // Any non-viewer can double-tap a date cell.
      // _startEditing will route them: historical → edit-request dialog,
      // today → direct edit (unless locked).  Admins bypass the dialog.
      final canEditDate = !isViewer;
      final inKey = 'DATE:$date:IN';
      final outKey = 'DATE:$date:OUT';
      final inIdx = _inventoryCachedColIndexByKey[inKey] ?? -1;
      final outIdx = _inventoryCachedColIndexByKey[outKey] ?? -1;
      if (inIdx >= 0 && !_isColumnHidden(inIdx)) {
        cells.add(dataCell(
          colKey: inKey,
          width: colWidthForKey(inKey),
          editable: canEditDate,
        ));
      }
      if (outIdx >= 0 && !_isColumnHidden(outIdx)) {
        cells.add(dataCell(
          colKey: outKey,
          width: colWidthForKey(outKey),
          editable: canEditDate,
        ));
      }
    }

    // Misc columns
    for (final col in miscCols) {
      final idx = _inventoryCachedColIndexByKey[col] ?? -1;
      if (idx < 0 || _isColumnHidden(idx)) continue;
      cells.add(dataCell(
        colKey: col,
        width: colWidthForKey(col),
        editable: isAdminOrEditor,
      ));
    }

    // Frozen right (auto-calculated)
    for (final col in frozenRight) {
      final idx = _inventoryCachedColIndexByKey[col] ?? -1;
      if (idx < 0 || _isColumnHidden(idx)) continue;
      cells.add(dataCell(
        colKey: col,
        width: colWidthForKey(col),
        editable: false,
        autoCalc: true,
      ));
    }

    final rowWidget = Row(children: cells);
    if (!hasNote) {
      return RepaintBoundary(child: rowWidget);
    }

    final rowLabel = displayRowNumber ?? _displayRowNumber(rowIndex);
    final productName =
        (productKey == null ? '' : (_data[rowIndex][productKey] ?? ''))
            .toString()
            .trim();
    final headerBase = isCommentNote ? 'Comment' : 'Discrepancy Notice';
    final header =
        noteTitle.isNotEmpty ? '$headerBase — $noteTitle' : headerBase;
    final typeLabel = isCommentNote ? 'Comment' : 'Discrepancy';
    final tooltipMessage = [
      header,
      'Type: $typeLabel',
      if (productName.isNotEmpty) 'Product: $productName',
      'Row: $rowLabel',
      '',
      noteBody.isEmpty ? 'No notes provided.' : noteBody,
      '',
      'Tip: Right-click a cell in this row to edit or remove.',
    ].join('\n');

    return RepaintBoundary(
      child: Tooltip(
        message: tooltipMessage,
        waitDuration: const Duration(milliseconds: 200),
        child: isCommentNote
            ? rowWidget
            : Stack(
                children: [
                  rowWidget,
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppColors.primaryOrange,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //  Spreadsheet Grid – 4-panel layout with frozen headers & row nums
  // ═══════════════════════════════════════════════════════
  Widget _buildSpreadsheetGrid2() {
    // Width of data cells only (no row number column).
    double dataCellsWidth = 0;
    for (int c = 0; c < _columns.length; c++) {
      dataCellsWidth += _getVisibleColumnWidth(c);
    }
    // Total height of all data rows.
    double dataRowsHeight = 0;
    for (int r = 0; r < _data.length; r++) {
      dataRowsHeight += _getVisibleRowHeight(r);
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
                                  .where((e) => !_isRowHidden(e.key))
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
                                              .where(
                                                  (e) => !_isRowHidden(e.key))
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
      if (_isColumnHidden(c)) continue;
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
      if (_isRowHidden(r)) continue;
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
    final scheme = Theme.of(context).colorScheme;
    final tabBarBg = scheme.surfaceContainerHighest;
    final tabDivider = scheme.outlineVariant;
    final tabInnerDivider = scheme.outlineVariant.withValues(alpha: 0.7);
    final activeTabBg = scheme.surface;
    final inactiveTabText = scheme.onSurfaceVariant;
    final activeTabText = scheme.onSurface;
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
                child: Icon(Icons.add, size: 16, color: scheme.onSurface),
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
                        color: isActive ? activeTabText : inactiveTabText,
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
              onChanged: (v) {
                if (isReadOnly) return;
                if (_suppressFormulaBarChanged) return;
                if (_editingRow == null || _editingCol == null) return;

                // Feed Formula Bar typing into the same live pipeline.
                _editController.text = v;
                _editController.selection =
                    TextSelection.collapsed(offset: v.length);
              },
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
            ..._data
                .asMap()
                .entries
                .where((entry) => !_isRowHidden(entry.key))
                .map((entry) {
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
          child: Text(
            '$_kHeaderRowNumber',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: mutedIcon,
            ),
          ),
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
          ..._columns.asMap().entries.where((entry) {
            // Skip hidden columns
            return !_isColumnHidden(entry.key);
          }).map((entry) {
            final colIndex = entry.key;
            final colWidth = _getColumnWidth(colIndex);
            final bounds = _getSelectionBounds();
            final isColSelected = _selectedRow != null &&
                colIndex >= bounds['minCol']! &&
                colIndex <= bounds['maxCol']!;

            // Check if there are hidden columns adjacent (for visual indicator)
            final adjacentHidden = _findHiddenColumnsNear(colIndex);
            final hasHiddenLeft = adjacentHidden.any((c) => c < colIndex);
            final hasHiddenRight = adjacentHidden.any((c) => c > colIndex);

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
              onSecondaryTapDown: (details) {
                _showColumnHeaderContextMenu(
                    context, details.globalPosition, colIndex);
              },
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
                          // Green indicator if hidden columns to the left
                          left: hasHiddenLeft
                              ? const BorderSide(color: Colors.green, width: 2)
                              : BorderSide.none,
                        ),
                        color: isColSelected ? AppColors.lightBlue : headerBg,
                      ),
                      child: Text(
                        _displayColumnName(entry.value),
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
                            if (_canEditSheet()) {
                              _pushUndoSnapshot();
                            }
                            _isResizingColumn = true;
                            _resizingColumnIndex = colIndex;
                            _resizingStartX = details.globalPosition.dx;
                            _resizingStartWidth = colWidth;
                          },
                          onHorizontalDragUpdate: (details) {
                            if (_isResizingColumn &&
                                _resizingColumnIndex == colIndex) {
                              final delta = (details.globalPosition.dx -
                                      _resizingStartX) /
                                  _zoomLevel;
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
                            _markDirty();
                          },
                          child: Container(
                            width: 6,
                            color: Colors.transparent,
                          ),
                        ),
                      ),
                    ),
                    // Hidden columns indicator at right (if columns to the right are hidden)
                    if (hasHiddenRight)
                      Positioned(
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Container(
                          width: 2,
                          color: Colors.green,
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

    // Check if there are hidden rows adjacent (for visual indicator)
    final adjacentHidden = _findHiddenRowsNear(rowIndex);
    final hasHiddenAbove = adjacentHidden.any((r) => r < rowIndex);
    final hasHiddenBelow = adjacentHidden.any((r) => r > rowIndex);

    return SizedBox(
      width: _rowNumWidth,
      height: rowHeight,
      child: Stack(
        children: [
          // Main row header
          GestureDetector(
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
            onSecondaryTapDown: (details) {
              _showRowHeaderContextMenu(
                  context, details.globalPosition, rowIndex);
            },
            child: Container(
              decoration: BoxDecoration(
                border: Border(
                  right: BorderSide(color: gridBorder, width: 1),
                  bottom: BorderSide(color: gridBorder, width: 1),
                  // Green indicator if hidden rows above
                  top: hasHiddenAbove
                      ? const BorderSide(color: Colors.green, width: 2)
                      : BorderSide.none,
                ),
                color: isRowInSelection ? AppColors.lightBlue : rowHeaderBg,
              ),
              child: Center(
                child: Text(
                  _rowLabels[rowIndex],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isRowInSelection ? FontWeight.w600 : FontWeight.w400,
                    color:
                        isRowInSelection ? AppColors.primaryBlue : rowNumText,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ),
          ),

          // Resize handle at bottom edge
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeRow,
              child: GestureDetector(
                onVerticalDragStart: (details) {
                  if (_canEditSheet()) {
                    _pushUndoSnapshot();
                  }
                  _isResizingRow = true;
                  _resizingRowIndex = rowIndex;
                  _resizingStartY = details.globalPosition.dy;
                  _resizingStartHeight = rowHeight;
                },
                onVerticalDragUpdate: (details) {
                  if (_isResizingRow && _resizingRowIndex == rowIndex) {
                    final delta =
                        (details.globalPosition.dy - _resizingStartY) /
                            _zoomLevel;
                    final newHeight = (_resizingStartHeight + delta)
                        .clamp(_minRowHeight, _maxRowHeight);
                    setState(() {
                      _rowHeights[rowIndex] = newHeight;
                    });
                  }
                },
                onVerticalDragEnd: (details) {
                  _isResizingRow = false;
                  _resizingRowIndex = null;
                  _markDirty();
                },
                child: Container(
                  height: 6,
                  color: Colors.transparent,
                ),
              ),
            ),
          ),

          // Hidden rows indicator at bottom (if rows below are hidden)
          if (hasHiddenBelow)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                height: 2,
                color: Colors.green,
              ),
            ),
        ],
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
    final activeCellBg = _isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.25)
        : const Color(0xFFE8F0FE);
    final selectionBg = _isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.15)
        : const Color(0xFFD2E3FC);
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
          ..._columns.asMap().entries.where((entry) {
            // Skip hidden columns
            return !_isColumnHidden(entry.key);
          }).map((entry) {
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
              onSecondaryTapDown: (details) {
                if (_isResizingColumn || isCollapsed) return;
                // Select the cell first
                _selectCell(rowIndex, colIndex);
                // Then show context menu
                _showCellContextMenu(
                    context, details.globalPosition, rowIndex, colIndex);
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
                            ? activeCellBg
                            : isInSel
                                ? selectionBg
                                : (rowIndex % 2 == 0 ? rowEvenBg : rowOddBg);
                  }(),
                ),
                child: Stack(
                  children: [
                    // Cell content (hidden when collapsed)
                    if (!isCollapsed) ...[
                      if (isEditing)
                        CallbackShortcuts(
                          bindings: {
                            const SingleActivator(LogicalKeyboardKey.tab): () {
                              _handleEditTab(backwards: false);
                            },
                            const SingleActivator(LogicalKeyboardKey.tab,
                                shift: true): () {
                              _handleEditTab(backwards: true);
                            },
                          },
                          child: TextField(
                            controller: _editController,
                            focusNode: _focusNode,
                            inputFormatters: (_isInventoryTrackerSheet() &&
                                    _columns[colIndex].startsWith('DATE:') &&
                                    (_columns[colIndex].endsWith(':IN') ||
                                        _columns[colIndex].endsWith(':OUT')))
                                ? <TextInputFormatter>[
                                    FilteringTextInputFormatter.digitsOnly,
                                  ]
                                : null,
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
                          ),
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
                                color: color.withValues(alpha: 0.15),
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

  static final List<Map<String, dynamic>> _templates =
      _SheetScreenState._kTemplates;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dialogBg = isDark ? const Color(0xFF0F172A) : Colors.white;
    final surface = isDark ? const Color(0xFF111827) : Colors.white;
    final surface2 = isDark ? const Color(0xFF0B1220) : _SheetScreenState._kBg;
    final border =
        isDark ? const Color(0xFF334155) : _SheetScreenState._kBorder;
    final titleColor =
        isDark ? const Color(0xFFF1F5F9) : _SheetScreenState._kNavy;
    final bodyColor =
        isDark ? const Color(0xFF94A3B8) : _SheetScreenState._kGray;

    return Dialog(
      backgroundColor: dialogBg,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border, width: 1),
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
                      color: surface2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: border,
                        width: 1,
                      ),
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
                        Text(
                          'Choose a Template',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: titleColor,
                            letterSpacing: 0.2,
                          ),
                        ),
                        Text(
                          'Start your sheet with a pre-defined structure. You can customise it afterwards.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.3,
                            color: bodyColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                    color: bodyColor,
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Divider(height: 1, color: border),
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
                            color: isHovered ? surface2 : surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isHovered
                                  ? color.withValues(alpha: 0.55)
                                  : border,
                              width: 1.2,
                            ),
                            boxShadow: isHovered
                                ? [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: isDark ? 0.28 : 0.05,
                                      ),
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
                                      color: surface2,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: border,
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
                                        color: titleColor,
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
                                style: TextStyle(
                                  fontSize: 11,
                                  height: 1.25,
                                  color: bodyColor,
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
                                      color: surface2,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: border,
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
                                              color: surface2,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              border: Border.all(
                                                color: border,
                                              ),
                                            ),
                                            child: Text(
                                              '+${cols.length - 4} more',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: bodyColor,
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
              Divider(height: 1, color: border),
              const SizedBox(height: 12),

              // ── Footer ──
              Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 14,
                    color: bodyColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Templates pre-fill column headers and a sample row. All content is editable.',
                    style: TextStyle(
                      fontSize: 11,
                      color: bodyColor,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: bodyColor,
                    ),
                    child: const Text('Cancel'),
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
                    color: Colors.black.withValues(alpha: 0.28),
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
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 2),
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
                      color: p.color.withValues(alpha: 0.55),
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
                      color: Colors.black.withValues(alpha: 0.28),
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
                                color: Colors.white.withValues(alpha: 0.32),
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
    final scheme = Theme.of(context).colorScheme;
    final borderColor = widget.isYou
        ? scheme.primary
        : (widget.isEditing ? scheme.tertiary : scheme.outlineVariant);
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
              color: borderColor,
              width: widget.isYou ? 2.4 : 1.8,
            ),
            boxShadow: [
              BoxShadow(
                color: widget.isEditing
                    ? scheme.tertiary.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.10),
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
