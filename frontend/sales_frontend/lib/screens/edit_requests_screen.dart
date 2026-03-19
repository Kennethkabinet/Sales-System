import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

// cspell:ignore Colour collab

// ── Colour constants (shared tokens) ──
const Color _kNavy = AppColors.primaryBlue;
const Color _kBg = AppColors.bgLight;
const Color _kBorder = AppColors.border;
const Color _kGray = AppColors.grayText;

class EditRequestsScreen extends StatefulWidget {
  const EditRequestsScreen({super.key});

  @override
  State<EditRequestsScreen> createState() => _EditRequestsScreenState();
}

class _EditRequestsScreenState extends State<EditRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;
  String _statusFilter = 'All';
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final List<int> _itemsPerPageOptions = [10, 20, 50];

  static const List<String> _statusOptions = [
    'All',
    'pending',
    'approved',
    'rejected'
  ];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor => _isDark ? const Color(0xFF0B1220) : _kBg;
  Color get _surfaceColor => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _surfaceAltColor => _isDark ? const Color(0xFF0F172A) : _kBg;
  Color get _borderColor => _isDark ? const Color(0xFF334155) : _kBorder;
  Color get _textPrimary => _isDark ? const Color(0xFFE5E7EB) : _kNavy;
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : _kGray;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ─────────────────────────────────────────────────────────
  //  Data
  // ─────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getAllEditRequests(
        status: _statusFilter == 'All' ? null : _statusFilter,
      );
      if (mounted) {
        setState(() {
          _requests = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resolve(Map<String, dynamic> req, bool approved) async {
    final id = req['id'] as int;
    final sheetId = req['sheet_id'] as int;
    try {
      // Uses HTTP route which now also emits socket events via collab handler
      await ApiService.respondToEditRequest(
        sheetId: sheetId,
        requestId: id,
        approved: approved,
        rejectReason: approved ? null : 'Rejected by admin',
      );
      // Also fire via socket so grant_temp_access reaches the editor immediately
      // if the admin's socket is connected (singleton persists across pages).
      SocketService.instance.resolveEditRequest(
        requestId: id,
        approved: approved,
        rejectReason: approved ? null : 'Rejected by admin',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(approved ? 'Request approved.' : 'Request rejected.'),
          backgroundColor: approved ? Colors.green : Colors.red,
        ));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  Future<void> _deleteRequest(Map<String, dynamic> req) async {
    final id = req['id'] as int;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Edit Request'),
        content: const Text(
            'Are you sure you want to permanently delete this resolved request?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ApiService.deleteEditRequest(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Request deleted.'),
          backgroundColor: Colors.grey,
        ));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to delete: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  // ─────────────────────────────────────────────────────────
  //  Derived
  // ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _paged {
    final start = (_currentPage - 1) * _itemsPerPage;
    final end = (start + _itemsPerPage).clamp(0, _requests.length);
    return _requests.sublist(start, end);
  }

  int get _totalPages =>
      (_requests.length / _itemsPerPage).ceil().clamp(1, 9999);

  // ─────────────────────────────────────────────────────────
  //  Build
  // ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
            if (!_isLoading && _error == null && _requests.isNotEmpty)
              _buildPagination(),
          ],
        ),
      ),
    );
  }

  // ── Header ──
  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Review and approve or reject cell-edit requests.',
                  style: TextStyle(
                    fontSize: 13,
                    color: _textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: _textPrimary),
                tooltip: 'Refresh',
                onPressed: _load,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildFilterBar(),
        ],
      ),
    );
  }

  // ── Filter bar ──
  Widget _buildFilterBar() {
    return Row(children: [
      Text('Status:',
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _textPrimary)),
      const SizedBox(width: 8),
      ..._statusOptions.map((s) {
        final selected = _statusFilter == s;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(s == 'All' ? 'All' : _capitalize(s),
                style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : _textPrimary,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
            selected: selected,
            showCheckmark: true,
            checkmarkColor: Colors.white,
            selectedColor: s == 'pending'
                ? Colors.orange[700]
                : s == 'approved'
                    ? const Color(0xFF2E7D32)
                    : s == 'rejected'
                        ? const Color(0xFFB71C1C)
                        : _kNavy,
            backgroundColor: _surfaceColor,
            side:
                BorderSide(color: selected ? Colors.transparent : _borderColor),
            onSelected: (_) {
              setState(() {
                _statusFilter = s;
                _currentPage = 1;
              });
              _load();
            },
          ),
        );
      }),
      const Spacer(),
      Text('${_requests.length} result${_requests.length == 1 ? '' : 's'}',
          style: TextStyle(fontSize: 12, color: _textSecondary)),
    ]);
  }

  // ── Body ──
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          ElevatedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry')),
        ]),
      );
    }
    if (_requests.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_outline, color: Colors.green[400], size: 56),
          const SizedBox(height: 12),
          Text(
              'No ${_statusFilter == 'All' ? '' : '$_statusFilter '}edit requests.',
              style: TextStyle(fontSize: 15, color: Colors.grey[600])),
        ]),
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
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_surfaceAltColor),
            headingRowHeight: 52,
            dataRowMinHeight: 62,
            dataRowMaxHeight: 70,
            dividerThickness: 1.0,
            headingTextStyle: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _textSecondary,
              letterSpacing: 0.4,
            ),
            dataTextStyle: TextStyle(
                fontSize: 13,
                color: _isDark ? const Color(0xFFE5E7EB) : Colors.black87),
            columnSpacing: 36,
            horizontalMargin: 24,
            columns: const [
              DataColumn(label: Text('Sheet')),
              DataColumn(label: Text('Requester')),
              DataColumn(label: Text('Cell')),
              DataColumn(label: Text('Column')),
              DataColumn(label: Text('Proposed Value')),
              DataColumn(label: Text('Requested At')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Reviewed By')),
              DataColumn(label: Text('Actions')),
            ],
            rows: _paged.map(_buildRow).toList(),
          ),
        ),
      ),
    );
  }

  DataRow _buildRow(Map<String, dynamic> req) {
    final status = req['status'] as String? ?? 'pending';
    final isPending = status == 'pending';

    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = Colors.green[700]!;
        break;
      case 'rejected':
        statusColor = Colors.red[600]!;
        break;
      default:
        statusColor = Colors.orange[800]!;
    }

    final requestedAt = req['requested_at'] as String? ?? '';
    final displayDate = requestedAt.length >= 16
        ? requestedAt.substring(0, 16).replaceAll('T', ' ')
        : requestedAt;

    return DataRow(cells: [
      // Sheet name
      DataCell(Text(req['sheet_name'] as String? ?? '—',
          style: const TextStyle(fontWeight: FontWeight.w500))),
      // Requester
      DataCell(Text(req['requester_username'] as String? ?? '—')),
      // Cell ref
      DataCell(Text(req['cell_reference'] as String? ?? '—',
          style: const TextStyle(fontFamily: 'monospace'))),
      // Column name
      DataCell(SizedBox(
        width: 120,
        child: Text(req['column_name'] as String? ?? '—',
            overflow: TextOverflow.ellipsis),
      )),
      // Proposed value
      DataCell(SizedBox(
        width: 100,
        child: Text(req['proposed_value'] as String? ?? '—',
            overflow: TextOverflow.ellipsis),
      )),
      // Requested at
      DataCell(Text(displayDate,
          style: TextStyle(fontSize: 11, color: _textSecondary))),
      // Status badge
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: statusColor.withValues(alpha: 0.6)),
        ),
        child: Text(_capitalize(status),
            style: TextStyle(
                color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
      )),
      // Reviewed by
      DataCell(Text(req['reviewer_username'] as String? ?? '—',
          style: TextStyle(fontSize: 11, color: _textSecondary))),
      // Action buttons (only for pending)
      DataCell(isPending
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.check_circle,
                    color: Colors.green, size: 20),
                tooltip: 'Approve',
                onPressed: () => _resolve(req, true),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              IconButton(
                icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                tooltip: 'Reject',
                onPressed: () => _resolve(req, false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ])
          : IconButton(
              icon: Icon(Icons.delete_outline, color: _textSecondary, size: 20),
              tooltip: 'Delete request',
              onPressed: () => _deleteRequest(req),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            )),
    ]);
  }

  // ── Pagination ──
  Widget _buildPagination() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
      child: Row(children: [
        // Items per page
        Text('Show:',
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _textPrimary)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(10)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _itemsPerPage,
              isDense: true,
              items: _itemsPerPageOptions
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    _itemsPerPage = v;
                    _currentPage = 1;
                  });
                }
              },
            ),
          ),
        ),
        const Spacer(),
        // Page info
        Text('Page $_currentPage of $_totalPages',
            style: TextStyle(fontSize: 12, color: _textSecondary)),
        const SizedBox(width: 12),
        // Prev / Next
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed:
              _currentPage > 1 ? () => setState(() => _currentPage--) : null,
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: _currentPage < _totalPages
              ? () => setState(() => _currentPage++)
              : null,
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ]),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
