import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/data_provider.dart';
import '../models/audit_log.dart';

// ── Colour constants (matches dashboard) ──
const Color _kContentBg = Color(0xFFFDF5F0);
const Color _kNavy = Color(0xFF1E3A6E);

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

  // ════════════════════════════════════════════
  //  Build
  // ════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kContentBg,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Title ──
            const Text(
              'AUDIT HISTORY',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: _kNavy,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 18),

            // ── Filter row ──
            _buildFilterRow(),
            const SizedBox(height: 20),

            // ── Log entries ──
            Expanded(
              child: Consumer<DataProvider>(
                builder: (context, data, _) {
                  if (data.isLoading && data.auditLogs.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
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

                  // Calculate pagination
                  final totalItems = data.auditLogs.length;
                  final totalPages = (totalItems / _itemsPerPage).ceil();

                  // Ensure current page is valid
                  if (_currentPage > totalPages && totalPages > 0) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      setState(() => _currentPage = totalPages);
                    });
                  }

                  final startIndex = (_currentPage - 1) * _itemsPerPage;
                  final endIndex =
                      (startIndex + _itemsPerPage).clamp(0, totalItems);
                  final paginatedLogs = data.auditLogs.sublist(
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
                      _buildPaginationControls(totalItems, totalPages),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
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
          const SizedBox(width: 16),

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
          const SizedBox(width: 16),

          // Time filter
          Expanded(
            child: _buildDropdown<String>(
              value: _timeFilter,
              hint: 'All Time',
              items: const [
                DropdownMenuItem(value: 'All Time', child: Text('All Time')),
                DropdownMenuItem(value: 'Today', child: Text('Today')),
                DropdownMenuItem(value: 'This Week', child: Text('This Week')),
                DropdownMenuItem(
                    value: 'This Month', child: Text('This Month')),
                DropdownMenuItem(value: 'Custom', child: Text('Custom Range…')),
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
          const SizedBox(width: 16),

          // Clear button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _clearFilters,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close, size: 16, color: Colors.grey[700]),
                    const SizedBox(width: 6),
                    Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(24),
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
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
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
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
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
              IconButton(
                icon: Icon(Icons.chevron_left,
                    color: _currentPage > 1 ? _kNavy : Colors.grey[400]),
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
                tooltip: 'Previous page',
                splashRadius: 20,
              ),

              // Page numbers
              ..._buildPageNumbers(totalPages),

              // Next button
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color:
                        _currentPage < totalPages ? _kNavy : Colors.grey[400]),
                onPressed: _currentPage < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
                tooltip: 'Next page',
                splashRadius: 20,
              ),
            ],
          ),
        ],
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
          width: 36,
          height: 36,
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
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
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
//  Single Audit Log Tile (matches screenshot)
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

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          // ── Main row ──
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Action icon
                  _buildActionIcon(),
                  const SizedBox(width: 14),

                  // Action badge
                  _buildActionBadge(),
                  const SizedBox(width: 14),

                  // Entity info
                  Expanded(child: _buildEntityInfo()),

                  // Expand arrow
                  Icon(
                    _expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: Colors.grey[500],
                    size: 26,
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded details ──
          if (_expanded) _buildDetails(),
        ],
      ),
    );
  }

  // ── Action icon (green for LOGIN/LOGOUT, teal for UPDATE, etc.) ──
  Widget _buildActionIcon() {
    final action = log.action.toUpperCase();
    Color bgColor;
    IconData icon;

    switch (action) {
      case 'LOGIN':
      case 'LOGOUT':
        bgColor = const Color(0xFF2E7D32); // dark green
        icon = action == 'LOGOUT' ? Icons.logout : Icons.login;
        break;
      case 'UPDATE':
        bgColor = const Color(0xFF00695C); // teal
        icon = Icons.edit_note;
        break;
      case 'CREATE':
        bgColor = const Color(0xFF2E7D32);
        icon = Icons.add_circle_outline;
        break;
      case 'DELETE':
        bgColor = const Color(0xFFC62828);
        icon = Icons.delete_outline;
        break;
      case 'EXPORT':
        bgColor = const Color(0xFF6A1B9A);
        icon = Icons.download;
        break;
      default:
        bgColor = Colors.grey;
        icon = Icons.info_outline;
    }

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: Colors.white, size: 22),
    );
  }

  // ── Action badge (bordered label) ──
  Widget _buildActionBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade400),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        log.action.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: _kNavy,
          letterSpacing: 0.3,
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
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kNavy,
              ),
            ),
            if (log.entityName != null) ...[
              Text(
                ' - ${log.entityName}',
                style: TextStyle(fontSize: 13, color: Colors.grey[700]),
              ),
            ] else if (log.description != null &&
                log.description!.isNotEmpty) ...[
              Flexible(
                child: Text(
                  ' - ${log.description}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              log.userName ?? 'Unknown',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
            const SizedBox(width: 16),
            Icon(Icons.access_time, size: 12, color: Colors.grey[400]),
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
      padding: const EdgeInsets.fromLTRB(74, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (log.description != null && log.description!.isNotEmpty) ...[
            Text('Description',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[600])),
            const SizedBox(height: 4),
            Text(log.description!, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 12),
          ],
          if (log.oldValue != null || log.newValue != null) ...[
            Text('Changes',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: Colors.grey[600])),
            const SizedBox(height: 8),
            Row(
              children: [
                if (log.oldValue != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Old Value',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.red[700])),
                          const SizedBox(height: 4),
                          Text(_formatValue(log.oldValue),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                if (log.oldValue != null && log.newValue != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Icon(Icons.arrow_forward,
                        size: 16, color: Colors.grey[400]),
                  ),
                if (log.newValue != null)
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('New Value',
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                  color: Colors.green[700])),
                          const SizedBox(height: 4),
                          Text(_formatValue(log.newValue),
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Icon(Icons.computer, size: 13, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text(
                'IP: ${log.ipAddress ?? 'Unknown'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
              const SizedBox(width: 16),
              Icon(Icons.person_outline, size: 13, color: Colors.grey[400]),
              const SizedBox(width: 4),
              Text(
                'User ID: ${log.userId ?? '-'}',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
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
