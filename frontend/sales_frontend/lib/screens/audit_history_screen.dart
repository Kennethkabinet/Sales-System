import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../models/audit_log.dart';
import '../config/constants.dart';

// ── Colour palette inspired by the uploaded audit-history UI ──
const Color _kPageBg = Color(0xFFFAF0E6); // warm cream/linen background
const Color _kHeaderMaroon = Color(0xFF283593); // dark blue title
const Color _kNavy = AppColors.primaryBlue; // active state / links
const Color _kCardBg = Color(0xFFFFFFFF); // white card
const Color _kFilterBg = Color(0xFFFFFFFF); // filter bar white
const Color _kBorderLight = Color(0xFFDDD5CC); // warm-tinted border
const Color _kGreenAccent = Color(0xFF1B5E20); // LOGIN / CREATE accent (dark green)
const Color _kOrangeAccent = Color(0xFFD4760A); // UPDATE accent (dark amber)
const Color _kRedAccent = Color(0xFFB71C1C); // DELETE accent (dark red)
const Color _kBlueAccent = Color(0xFF0D47A1); // EXPORT accent (dark blue)
const Color _kGrayAccent = Color(0xFF546E7A); // default/fallback accent

class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});

  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  String? _actionFilter;
  String? _entityFilter;
  String _timeFilter = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;
  String? _deptFilter; // V2: department filter
  String _cellRefFilter = ''; // V2: cell reference filter (e.g. "B4")

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final List<int> _itemsPerPageOptions = [10, 20, 50];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadAuditLogs();
    });
  }

  // ── colour helper for action types ──
  static Color _accentForAction(String action) {
    switch (action.toUpperCase()) {
      case 'LOGIN':
      case 'LOGOUT':
      case 'CREATE':
        return _kGreenAccent;
      case 'UPDATE':
        return _kOrangeAccent;
      case 'DELETE':
        return _kRedAccent;
      case 'EXPORT':
        return _kBlueAccent;
      default:
        return _kGrayAccent;
    }
  }

  // ════════════════════════════════════════════
  //  Build
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kPageBg,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──
            Text(
              'AUDIT HISTORY',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w900,
                color: _kHeaderMaroon,
                letterSpacing: 1.5,
                shadows: [
                  Shadow(
                    color: _kHeaderMaroon.withOpacity(0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Filter row ──
            _buildFilterRow(),
            const SizedBox(height: 20),

            // ── Log entries ──
            Expanded(
              child: Consumer<DataProvider>(
                builder: (context, data, _) {
                  if (data.isLoading && data.auditLogs.isEmpty) {
                    return Center(
                      child: CircularProgressIndicator(
                        color: _kHeaderMaroon,
                      ),
                    );
                  }

                  if (data.auditLogs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history,
                              size: 64, color: Colors.grey[300]),
                          const SizedBox(height: 16),
                          Text(
                            'No audit logs found',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  // ── V2 client-side filtering for dept & cell ref ──
                  var filteredLogs = data.auditLogs;
                  if (_deptFilter != null && _deptFilter!.isNotEmpty) {
                    filteredLogs = filteredLogs
                        .where((l) => l.departmentName == _deptFilter)
                        .toList();
                  }
                  if (_cellRefFilter.isNotEmpty) {
                    filteredLogs = filteredLogs
                        .where((l) =>
                            l.cellReference != null &&
                            l.cellReference!.toUpperCase() == _cellRefFilter)
                        .toList();
                  }

                  final filteredTotal = filteredLogs.length;
                  final filteredPages = filteredTotal == 0
                      ? 1
                      : (filteredTotal / _itemsPerPage).ceil();

                  // Ensure current page is valid
                  if (_currentPage > filteredPages && filteredPages > 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _currentPage = filteredPages);
                    });
                  }

                  final startIndex = (_currentPage - 1) * _itemsPerPage;
                  final endIndex =
                      (startIndex + _itemsPerPage).clamp(0, filteredTotal);
                  final paginatedLogs = filteredLogs.sublist(
                    startIndex,
                    endIndex,
                  );

                  return Column(
                    children: [
                      // List of audit logs
                      Expanded(
                        child: ListView.separated(
                          itemCount: paginatedLogs.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            return _AuditLogTile(log: paginatedLogs[index]);
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Pagination controls
                      _buildPaginationControls(filteredTotal, filteredPages),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Filter Row
  // ════════════════════════════════════════════
  Widget _buildFilterRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: _kFilterBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Action filter
              Expanded(
                child: _buildDropdown<String?>(
                  value: _actionFilter,
                  hint: 'All Actions',
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All Actions')),
                    DropdownMenuItem(value: 'CREATE', child: Text('Create')),
                    DropdownMenuItem(value: 'UPDATE', child: Text('Update')),
                    DropdownMenuItem(value: 'DELETE', child: Text('Delete')),
                    DropdownMenuItem(value: 'LOGIN', child: Text('Login')),
                    DropdownMenuItem(value: 'LOGOUT', child: Text('Logout')),
                    DropdownMenuItem(value: 'EXPORT', child: Text('Export')),
                  ],
                  onChanged: (v) {
                    setState(() => _actionFilter = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 14),

              // Entity filter
              Expanded(
                child: _buildDropdown<String?>(
                  value: _entityFilter,
                  hint: 'All Entities',
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All Entities')),
                    DropdownMenuItem(value: 'users', child: Text('Users')),
                    DropdownMenuItem(value: 'file', child: Text('Files')),
                    DropdownMenuItem(value: 'row', child: Text('Rows')),
                    DropdownMenuItem(value: 'formula', child: Text('Formulas')),
                    DropdownMenuItem(value: 'sheets', child: Text('Sheets')),
                  ],
                  onChanged: (v) {
                    setState(() => _entityFilter = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 14),

              // Time filter
              Expanded(
                child: _buildDropdown<String>(
                  value: _timeFilter,
                  hint: 'All Time',
                  items: const [
                    DropdownMenuItem(
                        value: 'All Time', child: Text('All Time')),
                    DropdownMenuItem(value: 'Today', child: Text('Today')),
                    DropdownMenuItem(
                        value: 'This Week', child: Text('This Week')),
                    DropdownMenuItem(
                        value: 'This Month', child: Text('This Month')),
                    DropdownMenuItem(
                        value: 'Custom', child: Text('Custom Range…')),
                  ],
                  onChanged: (v) async {
                    if (v == 'Custom') {
                      await _selectDateRange();
                    } else {
                      setState(() {
                        _timeFilter = v ?? 'All Time';
                        _computeDateRange();
                      });
                      _applyFilters();
                    }
                  },
                ),
              ),
              const SizedBox(width: 14),

              // Clear button
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: _clearFilters,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF0F0),
                      border: Border.all(color: const Color(0xFFE0B4B4)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.close, size: 16, color: _kHeaderMaroon),
                        const SizedBox(width: 6),
                        Text(
                          'Clear',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kHeaderMaroon,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // ── V2 Filters: department scope + cell reference ──
          Row(
            children: [
              // Department filter
              Expanded(
                flex: 2,
                child: _buildDropdown<String?>(
                  value: _deptFilter,
                  hint: 'All Departments',
                  items: const [
                    DropdownMenuItem(
                        value: null, child: Text('All Departments')),
                    DropdownMenuItem(value: 'IT', child: Text('IT')),
                    DropdownMenuItem(value: 'Finance', child: Text('Finance')),
                    DropdownMenuItem(value: 'HR', child: Text('HR')),
                    DropdownMenuItem(
                        value: 'Operations', child: Text('Operations')),
                    DropdownMenuItem(value: 'Sales', child: Text('Sales')),
                  ],
                  onChanged: (v) {
                    setState(() => _deptFilter = v);
                    _applyFilters();
                  },
                ),
              ),
              const SizedBox(width: 14),
              // Cell reference search
              Expanded(
                flex: 1,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    border: Border.all(color: _kBorderLight),
                    borderRadius: BorderRadius.circular(10),
                    color: Colors.white,
                  ),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Cell (e.g. B4)',
                      hintStyle:
                          TextStyle(color: Colors.grey[400], fontSize: 13),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      prefixIcon: Icon(Icons.grid_on,
                          size: 15, color: Colors.grey[400]),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 30, maxWidth: 30),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) {
                      setState(() => _cellRefFilter = v.trim().toUpperCase());
                      _applyFilters();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(flex: 2, child: SizedBox.shrink()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: _kBorderLight),
        borderRadius: BorderRadius.circular(10),
        color: Colors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down, color: Colors.grey[600]),
          style: TextStyle(fontSize: 13, color: Colors.grey[800]),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Pagination Controls
  // ════════════════════════════════════════════
  Widget _buildPaginationControls(int totalItems, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
      decoration: BoxDecoration(
        color: _kFilterBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items per page selector
          Row(
            children: [
              Text(
                'Show:',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: _kBorderLight),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _itemsPerPage,
                    isDense: true,
                    icon: Icon(Icons.arrow_drop_down,
                        size: 20, color: Colors.grey[600]),
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _itemsPerPageOptions.map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _itemsPerPage = value;
                          _currentPage = 1; // Reset to first page
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'entries',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(width: 24),
              Text(
                'Showing ${(_currentPage - 1) * _itemsPerPage + 1}-${((_currentPage - 1) * _itemsPerPage + _itemsPerPage).clamp(0, totalItems)} of $totalItems',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),

          // Page navigation
          Row(
            children: [
              // Previous button
              _buildNavArrow(
                icon: Icons.chevron_left,
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
                tooltip: 'Previous page',
              ),

              const SizedBox(width: 4),

              // Page numbers
              ..._buildPageNumbers(totalPages),

              const SizedBox(width: 4),

              // Next button
              _buildNavArrow(
                icon: Icons.chevron_right,
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
                tooltip: 'Next page',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNavArrow({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? _kNavy.withOpacity(0.08) : Colors.grey[100],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? _kNavy : Colors.grey[400],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    List<Widget> pageButtons = [];

    // Show up to 5 page numbers at a time
    int startPage = (_currentPage - 2).clamp(1, totalPages);
    int endPage = (startPage + 4).clamp(1, totalPages);

    // Adjust start if we're near the end
    if (endPage - startPage < 4) {
      startPage = (endPage - 4).clamp(1, totalPages);
    }

    // First page if not in range
    if (startPage > 1) {
      pageButtons.add(_buildPageButton(1));
      if (startPage > 2) {
        pageButtons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey[400])),
        ));
      }
    }

    // Page number buttons
    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(_buildPageButton(i));
    }

    // Last page if not in range
    if (endPage < totalPages) {
      if (endPage < totalPages - 1) {
        pageButtons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey[400])),
        ));
      }
      pageButtons.add(_buildPageButton(totalPages));
    }

    return pageButtons;
  }

  Widget _buildPageButton(int pageNumber) {
    final isActive = pageNumber == _currentPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() => _currentPage = pageNumber),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? _kNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? _kNavy : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Text(
            '$pageNumber',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: isActive ? Colors.white : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Filter Helpers
  // ════════════════════════════════════════════
  void _applyFilters() {
    setState(() {
      _currentPage = 1; // Reset to first page when filters change
    });
    context.read<DataProvider>().loadAuditLogs(
          action: _actionFilter,
          entity: _entityFilter,
          startDate: _startDate,
          endDate: _endDate,
        );
  }

  void _clearFilters() {
    setState(() {
      _actionFilter = null;
      _entityFilter = null;
      _timeFilter = 'All Time';
      _startDate = null;
      _endDate = null;
      _deptFilter = null;
      _cellRefFilter = '';
      _currentPage = 1; // Reset to first page
    });
    _applyFilters();
  }

  void _computeDateRange() {
    final now = DateTime.now();
    switch (_timeFilter) {
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = now;
        break;
      case 'This Week':
        _startDate = now.subtract(Duration(days: now.weekday - 1));
        _endDate = now;
        break;
      case 'This Month':
        _startDate = DateTime(now.year, now.month, 1);
        _endDate = now;
        break;
      default:
        _startDate = null;
        _endDate = null;
    }
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!, end: _endDate!)
          : null,
    );

    if (picked != null) {
      setState(() {
        _timeFilter = 'Custom';
        _startDate = picked.start;
        _endDate = picked.end;
      });
      _applyFilters();
    }
  }
}

// ════════════════════════════════════════════════
//  Single Audit Log Tile – redesigned with left
//  accent border & circular icon per the UI
// ════════════════════════════════════════════════
class _AuditLogTile extends StatefulWidget {
  final AuditLog log;
  const _AuditLogTile({required this.log});

  @override
  State<_AuditLogTile> createState() => _AuditLogTileState();
}

class _AuditLogTileState extends State<_AuditLogTile> {
  bool _expanded = false;

  AuditLog get log => widget.log;

  Color get _accent => _AuditHistoryScreenState._accentForAction(log.action);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kCardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kBorderLight.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            // ── Coloured left accent bar ──
            Container(width: 6, color: _accent),

            // ── Card content ──
            Expanded(
              child: Column(
                children: [
                  // ── Main row ──
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          // Circular action icon
                          _buildActionIcon(),
                          const SizedBox(width: 14),

                          // Action badge
                          _buildActionBadge(),
                          const SizedBox(width: 14),

                          // Entity info
                          Expanded(child: _buildEntityInfo()),

                          // Expand arrow
                          AnimatedRotation(
                            turns: _expanded ? 0.5 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: Colors.grey[500],
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Expanded details ──
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _buildDetails(),
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Circular action icon ──
  Widget _buildActionIcon() {
    final action = log.action.toUpperCase();
    IconData icon;

    switch (action) {
      case 'LOGIN':
        icon = Icons.login_rounded;
        break;
      case 'LOGOUT':
        icon = Icons.logout_rounded;
        break;
      case 'UPDATE':
        icon = Icons.edit_note_rounded;
        break;
      case 'CREATE':
        icon = Icons.add_circle_outline_rounded;
        break;
      case 'DELETE':
        icon = Icons.delete_outline_rounded;
        break;
      case 'EXPORT':
        icon = Icons.download_rounded;
        break;
      default:
        icon = Icons.info_outline_rounded;
    }

    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: _accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _accent.withOpacity(0.3),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  // ── Action badge (filled coloured label) ──
  Widget _buildActionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        log.action.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  // ── Entity info: entity type, user, description, time ──
  Widget _buildEntityInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              log.entityType,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.grey[800],
              ),
            ),
            if (log.entityName != null) ...[
              Text(
                ' - ',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
              Flexible(
                child: Text(
                  log.entityName!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else if (log.description != null &&
                log.description!.isNotEmpty) ...[
              Text(
                ' - ',
                style: TextStyle(fontSize: 13, color: Colors.grey[400]),
              ),
              Flexible(
                child: Text(
                  log.description!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Icon(Icons.person_outline_rounded,
                size: 13, color: Colors.grey[400]),
            const SizedBox(width: 4),
            Text(
              log.userName ?? 'Unknown',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[500],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 20),
            Icon(Icons.schedule_rounded, size: 13, color: Colors.grey[400]),
            const SizedBox(width: 4),
            Text(
              _timeAgo(log.timestamp),
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ],
    );
  }

  // ── Expanded detail panel ──
  Widget _buildDetails() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(76, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(height: 1, color: _kBorderLight),
          const SizedBox(height: 14),
          if (log.description != null && log.description!.isNotEmpty) ...[
            Text('Description',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(log.description!,
                style: TextStyle(fontSize: 13, color: Colors.grey[800])),
            const SizedBox(height: 14),
          ],
          if (log.oldValue != null || log.newValue != null) ...[
            Text('Changes',
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                if (log.oldValue != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF5F5),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: Colors.red[200]!, width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Old Value',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: Colors.red[700])),
                          const SizedBox(height: 4),
                          Text(_formatValue(log.oldValue),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[800])),
                        ],
                      ),
                    ),
                  ),
                if (log.oldValue != null && log.newValue != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.arrow_forward_rounded,
                        size: 18, color: Colors.grey[400]),
                  ),
                if (log.newValue != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0FFF4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: Colors.green[200]!, width: 0.8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Value',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                  color: Colors.green[700])),
                          const SizedBox(height: 4),
                          Text(_formatValue(log.newValue),
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[800])),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              Icon(Icons.computer_rounded, size: 13, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text(
                'IP: ${log.ipAddress ?? 'Unknown'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(width: 18),
              Icon(Icons.person_outline_rounded,
                  size: 13, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text(
                'User ID: ${log.userId ?? '-'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          // ── V2 fields: role, dept, cell ref ──
          if (log.role != null ||
              log.departmentName != null ||
              log.cellReference != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              children: [
                if (log.role != null)
                  _V2Badge(icon: Icons.shield_outlined, label: log.role!),
                if (log.departmentName != null)
                  _V2Badge(
                      icon: Icons.business_rounded,
                      label: log.departmentName!),
                if (log.cellReference != null)
                  _V2Badge(
                      icon: Icons.grid_on_rounded,
                      label: 'Cell ${log.cellReference}'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Helpers ──
  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hours ago';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  String _formatValue(dynamic value) {
    if (value == null) return 'null';
    if (value is Map) {
      return value.entries.map((e) => '${e.key}: ${e.value}').join('\n');
    }
    return value.toString();
  }
}

/// Small badge chip used in the V2 expanded detail row to show role/dept/cell ref.
class _V2Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _V2Badge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0EB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8CFC6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _kHeaderMaroon),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  color: _kHeaderMaroon,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
