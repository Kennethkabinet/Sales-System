import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

// ── Colour constants ──
const Color _kNavy = AppColors.darkText;
const Color _kAccent = AppColors.primaryBlue;
const Color _kBg = AppColors.white;

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
      if (mounted)
        setState(() {
          _requests = data;
          _isLoading = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
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
      backgroundColor: _kBg,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildFilterBar(),
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
    return Row(children: [
      const Icon(Icons.lock_open, color: _kAccent, size: 28),
      const SizedBox(width: 10),
      const Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Edit Requests',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w700, color: _kNavy)),
            SizedBox(height: 2),
            Text('Review and approve or reject editor cell-edit requests.',
                style: TextStyle(fontSize: 13, color: Colors.grey)),
          ],
        ),
      ),
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Refresh',
        onPressed: _load,
      ),
    ]);
  }

  // ── Filter bar ──
  Widget _buildFilterBar() {
    return Row(children: [
      const Text('Status:',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      const SizedBox(width: 8),
      ..._statusOptions.map((s) {
        final selected = _statusFilter == s;
        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ChoiceChip(
            label: Text(s == 'All' ? 'All' : _capitalize(s),
                style: TextStyle(
                    fontSize: 12,
                    color: selected ? Colors.white : _kNavy,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal)),
            selected: selected,
            selectedColor: s == 'pending'
                ? Colors.orange[700]
                : s == 'approved'
                    ? Colors.green[600]
                    : s == 'rejected'
                        ? Colors.red[600]
                        : _kAccent,
            backgroundColor: Colors.grey[100],
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
          style: TextStyle(fontSize: 12, color: Colors.grey[600])),
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
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SingleChildScrollView(
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF5F7FA)),
              headingTextStyle: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _kNavy),
              dataTextStyle:
                  const TextStyle(fontSize: 12, color: Colors.black87),
              columnSpacing: 24,
              horizontalMargin: 16,
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
          style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
      // Status badge
      DataCell(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: statusColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: statusColor.withOpacity(0.6)),
        ),
        child: Text(_capitalize(status),
            style: TextStyle(
                color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
      )),
      // Reviewed by
      DataCell(Text(req['reviewer_username'] as String? ?? '—',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]))),
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
              icon:
                  Icon(Icons.delete_outline, color: Colors.grey[500], size: 20),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(children: [
        // Items per page
        const Text('Show:',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(6)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _itemsPerPage,
              isDense: true,
              items: _itemsPerPageOptions
                  .map((v) => DropdownMenuItem(value: v, child: Text('$v')))
                  .toList(),
              onChanged: (v) {
                if (v != null)
                  setState(() {
                    _itemsPerPage = v;
                    _currentPage = 1;
                  });
              },
            ),
          ),
        ),
        const Spacer(),
        // Page info
        Text('Page $_currentPage of $_totalPages',
            style: TextStyle(fontSize: 12, color: Colors.grey[700])),
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
