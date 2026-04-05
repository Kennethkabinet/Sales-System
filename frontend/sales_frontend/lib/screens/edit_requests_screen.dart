import 'package:flutter/material.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import '../widgets/app_modal.dart';

// cspell:ignore Colour collab

// ── Colour constants (shared tokens) ──
const Color _kNavy = AppColors.primaryBlue;
const Color _kBg = AppColors.bgLight;
const Color _kBorder = AppColors.border;
const Color _kGray = AppColors.grayText;

class EditRequestsScreen extends StatefulWidget {
  final VoidCallback? onRequestsChanged;

  const EditRequestsScreen({super.key, this.onRequestsChanged});

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

  final ScrollController _hScroll = ScrollController();
  final ScrollController _vScroll = ScrollController();

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

  @override
  void dispose() {
    _hScroll.dispose();
    _vScroll.dispose();
    super.dispose();
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
      final resp = await ApiService.respondToEditRequest(
        sheetId: sheetId,
        requestId: id,
        approved: approved,
        rejectReason: approved ? null : 'Rejected by admin',
      );

      final updatedReq = resp['request'];
      final updatedStatus = updatedReq is Map
          ? (updatedReq['status']?.toString().toLowerCase())
          : null;
      final updatedRejectReason = updatedReq is Map
          ? (updatedReq['reject_reason']?.toString())
          : null;

      // Server may force-reject an approval attempt if it would violate
      // inventory rules (e.g. total quantity would become negative).
      final effectiveApproved = updatedStatus == 'approved'
          ? true
          : (updatedStatus == 'rejected' ? false : approved);

      if (mounted) {
        await AppModal.showText(
          context,
          title: effectiveApproved ? 'Request approved' : 'Request rejected',
          message: effectiveApproved
              ? 'Request approved.'
              : (updatedRejectReason?.isNotEmpty == true
                  ? updatedRejectReason!
                  : 'Request rejected.'),
        );
        widget.onRequestsChanged?.call();
        _load();
      }
    } catch (e) {
      if (mounted) {
        await AppModal.showText(
          context,
          title: 'Action failed',
          message: 'Failed: $e',
        );
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
        await AppModal.showText(
          context,
          title: 'Request deleted',
          message: 'Request deleted.',
        );
        widget.onRequestsChanged?.call();
        _load();
      }
    } catch (e) {
      if (mounted) {
        await AppModal.showText(
          context,
          title: 'Delete failed',
          message: 'Failed to delete: $e',
        );
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Scrollbar(
              controller: _hScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _hScroll,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: Scrollbar(
                    controller: _vScroll,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _vScroll,
                      child: DataTable(
                        headingRowColor:
                            WidgetStateProperty.all(_surfaceAltColor),
                        headingRowHeight: 44,
                        dataRowMinHeight: 52,
                        dataRowMaxHeight: 56,
                        dividerThickness: 1.0,
                        headingTextStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _textSecondary,
                          letterSpacing: 0.4,
                        ),
                        dataTextStyle: TextStyle(
                          fontSize: 13,
                          color: _isDark
                              ? const Color(0xFFE5E7EB)
                              : Colors.black87,
                        ),
                        columnSpacing: 18,
                        horizontalMargin: 16,
                        columns: const [
                          DataColumn(
                              label:
                                  SizedBox(width: 180, child: Text('Sheet'))),
                          DataColumn(
                              label: SizedBox(
                                  width: 90, child: Text('Requester'))),
                          DataColumn(
                              label: SizedBox(width: 70, child: Text('Cell'))),
                          DataColumn(
                              label:
                                  SizedBox(width: 200, child: Text('Column'))),
                          DataColumn(
                              label: SizedBox(
                                  width: 140, child: Text('Proposed Value'))),
                          DataColumn(
                              label: SizedBox(
                                  width: 140, child: Text('Requested At'))),
                          DataColumn(
                              label:
                                  SizedBox(width: 110, child: Text('Status'))),
                          DataColumn(
                              label: SizedBox(
                                  width: 110, child: Text('Reviewed By'))),
                          DataColumn(
                              label:
                                  SizedBox(width: 90, child: Text('Actions'))),
                        ],
                        rows: _paged.map(_buildRow).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _cellText(
    String text, {
    double? width,
    TextStyle? style,
    bool monospace = false,
    String? tooltip,
  }) {
    final effectiveText = text.isEmpty ? '—' : text;
    final effectiveStyle = monospace
        ? (style ?? const TextStyle()).copyWith(fontFamily: 'monospace')
        : style;

    final child = Text(
      effectiveText,
      overflow: TextOverflow.ellipsis,
      maxLines: 1,
      style: effectiveStyle,
    );

    final wrapped = Tooltip(message: tooltip ?? effectiveText, child: child);
    if (width == null) return wrapped;
    return SizedBox(width: width, child: wrapped);
  }

  String _formatColumnName(String raw) {
    final t = raw.trim();
    if (t.isEmpty || t == '—') return '—';

    // Inventory date columns: DATE:YYYY-MM-DD:IN / DATE:YYYY-MM-DD:OUT
    final m = RegExp(r'^DATE:(\d{4}-\d{2}-\d{2})(?::(IN|OUT))?$').firstMatch(t);
    if (m != null) {
      final date = m.group(1)!;
      final side = (m.group(2) ?? '').toUpperCase();
      if (side.isEmpty) return 'Date — $date';
      return '$side — $date';
    }

    // General cleanups (keep minimal): collapse underscores, trim.
    return t.replaceAll('_', ' ');
  }

  Widget _proposedValueCell(String raw) {
    final v = raw.trim().isEmpty ? '—' : raw.trim();
    final bg = _isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.18)
        : AppColors.primaryBlue.withValues(alpha: 0.10);
    final border = _isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.45)
        : AppColors.primaryBlue.withValues(alpha: 0.25);
    final textColor = _isDark ? const Color(0xFFE5E7EB) : _textPrimary;

    return SizedBox(
      width: 140,
      child: Tooltip(
        message: v,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border),
          ),
          child: Text(
            v,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: FontWeight.w700,
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

    final rawColumn = (req['column_name'] as String? ?? '—');
    final columnDisplay = _formatColumnName(rawColumn);

    final rawProposed = (req['proposed_value'] as String? ?? '—');

    return DataRow(cells: [
      // Sheet name
      DataCell(
        _cellText(
          (req['sheet_name'] as String? ?? '—').trim(),
          width: 180,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
      ),
      // Requester
      DataCell(
        _cellText(
          (req['requester_username'] as String? ?? '—').trim(),
          width: 90,
        ),
      ),
      // Cell ref
      DataCell(
        _cellText(
          (req['cell_reference'] as String? ?? '—').trim(),
          width: 70,
          monospace: true,
        ),
      ),
      // Column name
      DataCell(
        _cellText(
          columnDisplay,
          width: 200,
          tooltip: rawColumn.trim().isEmpty ? '—' : rawColumn.trim(),
        ),
      ),
      // Proposed value
      DataCell(_proposedValueCell(rawProposed)),
      // Requested at
      DataCell(
        _cellText(
          displayDate,
          width: 140,
          style: TextStyle(fontSize: 11, color: _textSecondary),
        ),
      ),
      // Status badge
      DataCell(SizedBox(
        width: 110,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: statusColor.withValues(alpha: 0.6)),
            ),
            child: Text(
              _capitalize(status),
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      )),
      // Reviewed by
      DataCell(
        _cellText(
          (req['reviewer_username'] as String? ?? '—').trim(),
          width: 110,
          style: TextStyle(fontSize: 11, color: _textSecondary),
        ),
      ),
      // Action buttons (only for pending)
      DataCell(SizedBox(
        width: 90,
        child: isPending
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.check_circle,
                      color: Colors.green, size: 20),
                  tooltip: 'Approve',
                  onPressed: () => _resolve(req, true),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                  tooltip: 'Reject',
                  onPressed: () => _resolve(req, false),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ])
            : Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: Icon(Icons.delete_outline,
                      color: _textSecondary, size: 20),
                  tooltip: 'Delete request',
                  onPressed: () => _deleteRequest(req),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 30, minHeight: 30),
                ),
              ),
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
