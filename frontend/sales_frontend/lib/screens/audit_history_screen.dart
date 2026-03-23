import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as xls;
import 'dart:io';
import '../providers/data_provider.dart';
import '../models/audit_log.dart';
import '../widgets/app_modal.dart';

// ── HireGround-style color palette ──
const Color _kBlue = Color(0xFF4285F4);
const Color _kNavy = Color(0xFF1F2937);
const Color _kGray = Color(0xFF6B7280);
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kBg = Color(0xFFF9FAFB);
const Color _kGreen = Color(0xFF22C55E);
const Color _kOrange = Color(0xFFF59E0B);
const Color _kRed = Color(0xFFEF4444);

class AuditHistoryScreen extends StatefulWidget {
  const AuditHistoryScreen({super.key});

  @override
  State<AuditHistoryScreen> createState() => _AuditHistoryScreenState();
}

class _AuditHistoryScreenState extends State<AuditHistoryScreen> {
  String? _actionFilter;
  String? _entityFilter;
  String _dateRangeFilter = 'All Time';
  DateTime? _startDate;
  DateTime? _endDate;
  final TextEditingController _searchCtrl = TextEditingController();
  int? _expandedIndex;
  bool _isExporting = false;

  // Pagination
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final List<int> _itemsPerPageOptions = [10, 20, 50];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor => _isDark ? const Color(0xFF0B1220) : _kBg;
  Color get _surfaceColor => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _surfaceAltColor => _isDark ? const Color(0xFF0F172A) : _kBg;
  Color get _borderColor => _isDark ? const Color(0xFF334155) : _kBorder;
  Color get _textPrimary => _isDark ? const Color(0xFFE5E7EB) : _kNavy;
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : _kGray;

  Color _actionTintBg(String action) {
    if (!_isDark) return _actionBgColor(action);
    final base = _actionColor(action);
    // Subtle tint that reads well on dark surfaces.
    return Color.alphaBlend(base.withValues(alpha: 0.20), _surfaceAltColor);
  }

  Color _actionTintFg(String action) {
    final base = _actionColor(action);
    return _isDark ? base.withValues(alpha: 0.95) : base;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadAuditLogs();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Export helpers
  // ─────────────────────────────────────────────────────────

  List<AuditLog> _filteredLogsForExport(List<AuditLog> allLogs) {
    var filtered = allLogs;

    if (_actionFilter != null) {
      filtered = filtered
          .where((l) => l.action.toUpperCase() == _actionFilter)
          .toList();
    }

    if (_entityFilter != null) {
      filtered = filtered
          .where((l) => l.entityType.toUpperCase() == _entityFilter)
          .toList();
    }

    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((l) {
        return (l.userName?.toLowerCase().contains(q) ?? false) ||
            l.action.toLowerCase().contains(q) ||
            l.entityType.toLowerCase().contains(q) ||
            (l.entityName?.toLowerCase().contains(q) ?? false) ||
            (_getDescription(l).toLowerCase().contains(q)) ||
            (l.ipAddress?.toLowerCase().contains(q) ?? false);
      }).toList();
    }

    return filtered;
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '-';
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }

  String _dateRangeLabel() {
    if (_dateRangeFilter != 'Custom') return _dateRangeFilter;
    final s =
        _startDate != null ? DateFormat('yyyy-MM-dd').format(_startDate!) : '-';
    final e =
        _endDate != null ? DateFormat('yyyy-MM-dd').format(_endDate!) : '-';
    return 'Custom ($s to $e)';
  }

  Future<void> _showExportMenu() async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = box.localToGlobal(Offset.zero, ancestor: overlay);
    final rect = Rect.fromLTWH(pos.dx, pos.dy, box.size.width, box.size.height);

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: const [
        PopupMenuItem(
          value: 'pdf',
          child: Row(
            children: [
              Icon(Icons.picture_as_pdf_rounded, size: 18),
              SizedBox(width: 10),
              Text('Export PDF Report'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'excel',
          child: Row(
            children: [
              Icon(Icons.table_chart_rounded, size: 18),
              SizedBox(width: 10),
              Text('Export Excel (.xlsx)'),
            ],
          ),
        ),
      ],
    );

    if (choice == null) return;
    if (choice == 'pdf') {
      await _exportPdf();
    } else if (choice == 'excel') {
      await _exportExcel();
    }
  }

  Future<void> _exportPdf() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);
    try {
      final data = context.read<DataProvider>();
      final logs = _filteredLogsForExport(data.auditLogs);

      if (logs.isEmpty) {
        await AppModal.showText(
          context,
          title: 'Nothing to export',
          message: 'No logs to export.',
        );
        return;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Audit Log PDF',
        fileName: 'audit_log_report_$timestamp.pdf',
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
      );
      if (savePath == null) return;

      final doc = pw.Document();

      PdfColor pdfColor(Color c) => PdfColor.fromInt(c.toARGB32() & 0x00FFFFFF);
      final brandBlue = pdfColor(_kBlue);
      final border = PdfColor.fromInt(0xE5E7EB);

      final headerStyle = pw.TextStyle(
        fontSize: 18,
        fontWeight: pw.FontWeight.bold,
        color: brandBlue,
      );
      final labelStyle = pw.TextStyle(
        fontSize: 10,
        color: PdfColors.grey700,
      );
      final valueStyle = pw.TextStyle(
        fontSize: 10,
        color: PdfColors.black,
      );

      final reportTitle = 'Audit Log Report';

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(24),
          footer: (context) => pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
            ),
          ),
          build: (context) {
            final subtitle =
                'Generated: ${_formatDateTime(DateTime.now())}   •   Total: ${logs.length}';
            final filters = <List<String>>[
              ['Action', _actionFilter ?? 'All'],
              ['Entity', _entityFilter ?? 'All'],
              ['Date Range', _dateRangeLabel()],
              [
                'Search',
                _searchCtrl.text.trim().isEmpty ? '-' : _searchCtrl.text.trim()
              ],
            ];

            final tableHeaders = [
              'Date/Time',
              'User',
              'Action',
              'Entity',
              'Entity Name',
              'Description',
              'IP',
            ];

            String ellipsize(String s, int max) {
              if (s.length <= max) return s;
              return '${s.substring(0, max - 1)}…';
            }

            final tableData = logs.map((l) {
              return [
                _formatDateTime(l.timestamp),
                (l.userName ?? '-'),
                l.action.toUpperCase(),
                l.entityType.toUpperCase(),
                (l.entityName ?? '-'),
                ellipsize(_getDescription(l), 90),
                (l.ipAddress ?? '-'),
              ];
            }).toList();

            return [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(reportTitle, style: headerStyle),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        subtitle,
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: border, width: 1),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: filters
                          .map(
                            (f) => pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 2),
                              child: pw.Row(
                                mainAxisSize: pw.MainAxisSize.min,
                                children: [
                                  pw.SizedBox(
                                    width: 72,
                                    child: pw.Text(
                                      '${f[0]}:',
                                      style: labelStyle,
                                    ),
                                  ),
                                  pw.Text(f[1], style: valueStyle),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 14),
              pw.TableHelper.fromTextArray(
                headers: tableHeaders,
                data: tableData,
                headerDecoration: pw.BoxDecoration(
                  color: PdfColors.grey200,
                  border: pw.Border.all(color: border, width: 1),
                ),
                cellStyle: const pw.TextStyle(fontSize: 8),
                headerStyle: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
                cellAlignment: pw.Alignment.centerLeft,
                headerAlignment: pw.Alignment.centerLeft,
                border: pw.TableBorder.all(color: border, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.4),
                  1: const pw.FlexColumnWidth(1.0),
                  2: const pw.FlexColumnWidth(0.7),
                  3: const pw.FlexColumnWidth(0.9),
                  4: const pw.FlexColumnWidth(1.1),
                  5: const pw.FlexColumnWidth(2.7),
                  6: const pw.FlexColumnWidth(1.0),
                },
              ),
            ];
          },
        ),
      );

      final bytes = await doc.save();
      await File(savePath).writeAsBytes(bytes);

      if (!mounted) return;
      await AppModal.showText(
        context,
        title: 'Export complete',
        message: 'Saved PDF: $savePath',
      );
    } catch (e) {
      if (!mounted) return;
      await AppModal.showText(
        context,
        title: 'Export failed',
        message: 'Export failed: $e',
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportExcel() async {
    if (_isExporting) return;

    setState(() => _isExporting = true);
    try {
      final data = context.read<DataProvider>();
      final logs = _filteredLogsForExport(data.auditLogs);

      if (logs.isEmpty) {
        await AppModal.showText(
          context,
          title: 'Nothing to export',
          message: 'No logs to export.',
        );
        return;
      }

      final timestamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Audit Log Excel',
        fileName: 'audit_log_report_$timestamp.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (savePath == null) return;

      final book = xls.Excel.createExcel();
      final sheet = book['Audit Logs'];

      // Header row
      final headers = [
        'Date/Time',
        'User',
        'Action',
        'Entity',
        'Entity Name',
        'Description',
        'IP',
      ];
      sheet.appendRow(headers.map((h) => xls.TextCellValue(h)).toList());

      // Bold headers
      final headerStyle = xls.CellStyle(
        bold: true,
        backgroundColorHex: xls.ExcelColor.fromHexString('FFE5E7EB'),
      );
      for (var c = 0; c < headers.length; c++) {
        final cell = sheet.cell(
          xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0),
        );
        cell.cellStyle = headerStyle;
      }

      for (final l in logs) {
        sheet.appendRow([
          xls.TextCellValue(_formatDateTime(l.timestamp)),
          xls.TextCellValue(l.userName ?? '-'),
          xls.TextCellValue(l.action.toUpperCase()),
          xls.TextCellValue(l.entityType.toUpperCase()),
          xls.TextCellValue(l.entityName ?? '-'),
          xls.TextCellValue(_getDescription(l)),
          xls.TextCellValue(l.ipAddress ?? '-'),
        ]);
      }

      // Remove the default "Sheet1" if present and unused
      if (book.sheets.keys.contains('Sheet1') && book.sheets.keys.length > 1) {
        book.delete('Sheet1');
      }

      final bytes = book.encode();
      if (bytes == null) {
        throw Exception('Failed to generate Excel bytes');
      }
      await File(savePath).writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await AppModal.showText(
        context,
        title: 'Export complete',
        message: 'Saved Excel: $savePath',
      );
    } catch (e) {
      if (!mounted) return;
      await AppModal.showText(
        context,
        title: 'Export failed',
        message: 'Export failed: $e',
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── Action badge colors ──
  static Color _actionColor(String action) {
    switch (action.toUpperCase()) {
      case 'LOGIN':
        return const Color(0xFF059669);
      case 'LOGOUT':
        return const Color(0xFFDC2626);
      case 'CREATE':
        return _kGreen;
      case 'UPDATE':
        return _kOrange;
      case 'DELETE':
        return _kRed;
      case 'EXPORT':
        return _kBlue;
      default:
        return _kGray;
    }
  }

  static Color _actionBgColor(String action) {
    switch (action.toUpperCase()) {
      case 'LOGIN':
        return const Color(0xFFD1FAE5);
      case 'LOGOUT':
        return const Color(0xFFFEE2E2);
      case 'CREATE':
        return const Color(0xFFDCFCE7);
      case 'UPDATE':
        return const Color(0xFFFEF3C7);
      case 'DELETE':
        return const Color(0xFFFEE2E2);
      case 'EXPORT':
        return const Color(0xFFDBEAFE);
      default:
        return const Color(0xFFF3F4F6);
    }
  }

  // ── Auto-generate description if missing ──
  static String _getDescription(AuditLog log) {
    if (log.description != null && log.description!.isNotEmpty) {
      return log.description!;
    }

    final action = log.action.toUpperCase();
    final entity = log.entityType.toLowerCase();
    final entityName = log.entityName ?? '';
    final userName = log.userName ?? 'User';

    switch (action) {
      case 'LOGIN':
        return '$userName logged into the system';
      case 'LOGOUT':
        return '$userName logged out of the system';
      case 'CREATE':
        return entityName.isNotEmpty
            ? 'Created new $entity "$entityName"'
            : 'Created new $entity';
      case 'UPDATE':
        return entityName.isNotEmpty
            ? 'Updated $entity "$entityName"'
            : 'Updated $entity record';
      case 'DELETE':
        return entityName.isNotEmpty
            ? 'Deleted $entity "$entityName"'
            : 'Deleted $entity record';
      case 'EXPORT':
        return entityName.isNotEmpty
            ? 'Exported $entity "$entityName"'
            : 'Exported $entity data';
      default:
        return 'Performed $action on $entity';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Main card container ──
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: _surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  children: [
                    // ── Header with title, search, filters, export ──
                    _buildTableHeader(),

                    // ── Table content ──
                    Expanded(
                      child: Consumer<DataProvider>(
                        builder: (context, data, _) {
                          if (data.isLoading && data.auditLogs.isEmpty) {
                            return Center(
                              child: CircularProgressIndicator(color: _kBlue),
                            );
                          }

                          if (data.auditLogs.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.history,
                                      size: 56,
                                      color: _isDark
                                          ? const Color(0xFF334155)
                                          : Colors.grey[300]),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No audit logs found',
                                    style: TextStyle(
                                        fontSize: 15, color: _textSecondary),
                                  ),
                                ],
                              ),
                            );
                          }

                          // Apply filters
                          var filteredLogs = data.auditLogs;

                          // Action filter
                          if (_actionFilter != null) {
                            filteredLogs = filteredLogs
                                .where((l) =>
                                    l.action.toUpperCase() == _actionFilter)
                                .toList();
                          }

                          // Entity filter
                          if (_entityFilter != null) {
                            filteredLogs = filteredLogs
                                .where((l) =>
                                    l.entityType.toUpperCase() == _entityFilter)
                                .toList();
                          }

                          // Search filter
                          final searchQuery = _searchCtrl.text.toLowerCase();
                          if (searchQuery.isNotEmpty) {
                            filteredLogs = filteredLogs.where((l) {
                              return (l.userName
                                          ?.toLowerCase()
                                          .contains(searchQuery) ??
                                      false) ||
                                  (l.entityType
                                      .toLowerCase()
                                      .contains(searchQuery)) ||
                                  (l.entityName
                                          ?.toLowerCase()
                                          .contains(searchQuery) ??
                                      false) ||
                                  (_getDescription(l)
                                      .toLowerCase()
                                      .contains(searchQuery)) ||
                                  (l.action
                                      .toLowerCase()
                                      .contains(searchQuery));
                            }).toList();
                          }

                          final filteredTotal = filteredLogs.length;
                          final filteredPages = filteredTotal == 0
                              ? 1
                              : (filteredTotal / _itemsPerPage).ceil();

                          // Ensure current page is valid
                          if (_currentPage > filteredPages &&
                              filteredPages > 0) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              setState(() => _currentPage = filteredPages);
                            });
                          }

                          // Calculate valid page for current render
                          final validPage =
                              _currentPage.clamp(1, filteredPages);
                          final startIndex = ((validPage - 1) * _itemsPerPage)
                              .clamp(0, filteredTotal);
                          final endIndex = (startIndex + _itemsPerPage)
                              .clamp(0, filteredTotal);
                          final paginatedLogs = startIndex < filteredTotal
                              ? filteredLogs.sublist(startIndex, endIndex)
                              : <AuditLog>[];

                          return Column(
                            children: [
                              // ── Table header row ──
                              _buildTableColumnHeaders(),

                              // ── Table rows ──
                              Expanded(
                                child: ListView.builder(
                                  itemCount: paginatedLogs.length,
                                  itemBuilder: (context, index) {
                                    final log = paginatedLogs[index];
                                    final isExpanded = _expandedIndex == index;
                                    return _buildTableRow(
                                        log, index, isExpanded);
                                  },
                                ),
                              ),

                              // ── Footer with pagination ──
                              _buildTableFooter(filteredTotal, filteredPages),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Table Header (Title, Search, Filters, Export)
  // ════════════════════════════════════════════
  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          // Modern Search box
          Expanded(
            flex: 2,
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _surfaceColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 14, color: _textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search logs...',
                  hintStyle: TextStyle(
                      fontSize: 14,
                      color: _textSecondary.withValues(alpha: 0.8)),
                  prefixIcon: Container(
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    child: Icon(Icons.search_rounded,
                        size: 20, color: _textSecondary),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 44),
                  suffixIcon: _searchCtrl.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              size: 18, color: _textSecondary),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Action filter dropdown
          _buildModernDropdown(
            value: _actionFilter,
            hint: 'All Action',
            icon: Icons.bolt_rounded,
            items: const [
              'LOGIN',
              'LOGOUT',
              'CREATE',
              'UPDATE',
              'DELETE',
              'EXPORT'
            ],
            onChanged: (v) => setState(() => _actionFilter = v),
          ),
          const SizedBox(width: 10),

          // Entity filter dropdown
          _buildModernDropdown(
            value: _entityFilter,
            hint: 'All Entity',
            icon: Icons.category_rounded,
            items: const [
              'USERS',
              'SHEETS',
              'CELL',
              'INVENTORY',
              'FILE',
              'FOLDERS'
            ],
            onChanged: (v) => setState(() => _entityFilter = v),
          ),
          const SizedBox(width: 10),

          // Date range dropdown
          _buildDateRangeDropdown(),
          const SizedBox(width: 16),

          // Export button
          ElevatedButton.icon(
            onPressed: _isExporting ? null : _showExportMenu,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(_isExporting ? 'Exporting...' : 'Export'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDropdown({
    required String? value,
    required String hint,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return PopupMenuButton<String?>(
      onSelected: (selected) {
        // Always call onChanged, even if selecting the same value
        onChanged(selected);
      },
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        PopupMenuItem<String?>(
          value: null,
          child: Row(
            children: [
              Icon(icon, size: 18, color: _kGray),
              const SizedBox(width: 10),
              Text(hint, style: TextStyle(fontSize: 13, color: _textPrimary)),
              if (value == null) ...[
                const Spacer(),
                Icon(Icons.check, size: 16, color: _kBlue),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...items.map((item) => PopupMenuItem<String>(
              value: item,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item == value ? _kBlue : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(item,
                      style: TextStyle(fontSize: 13, color: _textPrimary)),
                  if (item == value) ...[
                    const Spacer(),
                    Icon(Icons.check, size: 16, color: _kBlue),
                  ],
                ],
              ),
            )),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: value != null ? _kBlue.withValues(alpha: 0.08) : _surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color:
                  value != null ? _kBlue.withValues(alpha: 0.3) : _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: value != null ? _kBlue : _textSecondary),
            const SizedBox(width: 8),
            Text(
              value ?? hint,
              style: TextStyle(
                fontSize: 13,
                color: value != null ? _kBlue : _textSecondary,
                fontWeight: value != null ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: value != null ? _kBlue : _textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeDropdown() {
    final options = ['All Time', 'Custom'];
    return PopupMenuButton<String>(
      initialValue: _dateRangeFilter,
      onSelected: (value) async {
        if (value == 'Custom') {
          await _selectDateRange();
        } else {
          setState(() {
            _dateRangeFilter = value;
            _computeDateRange(value);
          });
          // Adjust end date to end of day for inclusive filtering
          final adjustedEndDate = _endDate != null
              ? DateTime(
                  _endDate!.year, _endDate!.month, _endDate!.day, 23, 59, 59)
              : null;
          context.read<DataProvider>().loadAuditLogs(
                startDate: _startDate,
                endDate: adjustedEndDate,
              );
        }
      },
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => options
          .map((option) => PopupMenuItem<String>(
                value: option,
                child: Row(
                  children: [
                    Icon(
                      option == 'Custom'
                          ? Icons.date_range_rounded
                          : Icons.schedule_rounded,
                      size: 18,
                      color: option == _dateRangeFilter ? _kBlue : _kGray,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      option,
                      style: TextStyle(
                        fontSize: 13,
                        color: _textPrimary,
                        fontWeight: option == _dateRangeFilter
                            ? FontWeight.w500
                            : FontWeight.w400,
                      ),
                    ),
                    if (option == _dateRangeFilter) ...[
                      const Spacer(),
                      Icon(Icons.check, size: 16, color: _kBlue),
                    ],
                  ],
                ),
              ))
          .toList(),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _dateRangeFilter != 'All Time'
              ? _kBlue.withValues(alpha: 0.08)
              : _surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _dateRangeFilter != 'All Time'
                ? _kBlue.withValues(alpha: 0.3)
                : _borderColor,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size: 16,
              color: _dateRangeFilter != 'All Time' ? _kBlue : _textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              _dateRangeFilter,
              style: TextStyle(
                fontSize: 13,
                color: _dateRangeFilter != 'All Time' ? _kBlue : _textSecondary,
                fontWeight: _dateRangeFilter != 'All Time'
                    ? FontWeight.w500
                    : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: _dateRangeFilter != 'All Time' ? _kBlue : _textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  void _computeDateRange(String filter) {
    final now = DateTime.now();
    switch (filter) {
      case 'Today':
        _startDate = DateTime(now.year, now.month, now.day);
        _endDate = now;
        break;
      case 'Last 7 Days':
        _startDate = now.subtract(const Duration(days: 7));
        _endDate = now;
        break;
      case 'Last 30 Days':
        _startDate = now.subtract(const Duration(days: 30));
        _endDate = now;
        break;
      default:
        _startDate = null;
        _endDate = null;
    }
  }

  // ════════════════════════════════════════════
  //  Table Column Headers
  // ════════════════════════════════════════════
  Widget _buildTableColumnHeaders() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceAltColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          _headerCell('USER', flex: 2),
          _headerCell('ACTION', flex: 1),
          _headerCell('ENTITY', flex: 2),
          _headerCell('DESCRIPTION', flex: 3),
          _headerCell('TIMESTAMP', flex: 2),
          const SizedBox(width: 60), // Actions column
        ],
      ),
    );
  }

  Widget _headerCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Table Row
  // ════════════════════════════════════════════
  Widget _buildTableRow(AuditLog log, int index, bool isExpanded) {
    return Column(
      children: [
        InkWell(
          onTap: () =>
              setState(() => _expandedIndex = isExpanded ? null : index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: isExpanded
                  ? _kBlue.withValues(alpha: 0.04)
                  : (index.isOdd
                      ? _surfaceAltColor.withValues(alpha: 0.8)
                      : _surfaceColor),
              border: Border(
                  bottom:
                      BorderSide(color: _borderColor.withValues(alpha: 0.5))),
            ),
            child: Row(
              children: [
                // User column with avatar
                Expanded(
                  flex: 2,
                  child: Row(
                    children: [
                      _buildUserAvatar(log.userName ?? 'U'),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              log.userName ?? 'Unknown',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (log.role != null)
                              Text(
                                log.role!,
                                style: TextStyle(
                                    fontSize: 11, color: _textSecondary),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Action badge - more compact
                Expanded(
                  flex: 1,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildActionBadge(log.action),
                  ),
                ),

                // Entity
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        log.entityType.toLowerCase(),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _textPrimary,
                        ),
                      ),
                      if (log.entityName != null)
                        Text(
                          log.entityName!,
                          style: TextStyle(fontSize: 11, color: _textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),

                // Description - auto-generated if missing
                Expanded(
                  flex: 3,
                  child: Text(
                    _getDescription(log),
                    style: TextStyle(
                        fontSize: 13,
                        color: _textPrimary.withValues(alpha: 0.85)),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),

                // Timestamp
                Expanded(
                  flex: 2,
                  child: Text(
                    _formatTimestamp(log.timestamp),
                    style: TextStyle(fontSize: 12, color: _textSecondary),
                  ),
                ),

                // Expand icon
                SizedBox(
                  width: 36,
                  child: AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: isExpanded ? _kBlue : _textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded details - Gmail-style
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: _buildExpandedDetails(log),
          crossFadeState:
              isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  Widget _buildUserAvatar(String name) {
    final initials = name.isNotEmpty
        ? name
            .split(' ')
            .map((e) => e.isNotEmpty ? e[0] : '')
            .take(2)
            .join()
            .toUpperCase()
        : '?';
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_kBlue, _kBlue.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildActionBadge(String action) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _actionTintBg(action),
        borderRadius: BorderRadius.circular(4),
        border: _isDark
            ? Border.all(color: _actionTintFg(action).withValues(alpha: 0.30))
            : null,
      ),
      child: Text(
        action.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _actionTintFg(action),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Expanded Details - Gmail-style full view
  // ════════════════════════════════════════════
  Widget _buildExpandedDetails(AuditLog log) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with action and timestamp
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _surfaceAltColor,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                // Action icon
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _actionTintBg(log.action),
                    borderRadius: BorderRadius.circular(10),
                    border: _isDark
                        ? Border.all(
                            color: _actionTintFg(log.action)
                                .withValues(alpha: 0.25),
                          )
                        : null,
                  ),
                  child: Icon(
                    _getActionIcon(log.action),
                    color: _actionTintFg(log.action),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                // Action title and description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          _buildActionBadge(log.action),
                          const SizedBox(width: 10),
                          Text(
                            log.entityType,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _textPrimary,
                            ),
                          ),
                          if (log.entityName != null) ...[
                            Text(' • ',
                                style: TextStyle(color: _textSecondary)),
                            Flexible(
                              child: Text(
                                log.entityName!,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _textPrimary.withValues(alpha: 0.85),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _getDescription(log),
                        style: TextStyle(fontSize: 13, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
                // Full timestamp
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _formatFullDate(log.timestamp),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      _formatTime(log.timestamp),
                      style: TextStyle(fontSize: 11, color: _textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Details section
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // User info row
                _buildDetailRow(
                  icon: Icons.person_outline_rounded,
                  label: 'Performed by',
                  value: log.userName ?? 'Unknown',
                  extra: log.role != null ? ' (${log.role})' : null,
                ),
                const SizedBox(height: 12),

                // Entity info
                _buildDetailRow(
                  icon: Icons.category_outlined,
                  label: 'Entity Type',
                  value: log.entityType,
                ),
                const SizedBox(height: 12),

                // Log ID
                _buildDetailRow(
                  icon: Icons.tag_rounded,
                  label: 'Log ID',
                  value: '#${log.id}',
                ),

                if (log.departmentName != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    icon: Icons.business_rounded,
                    label: 'Department',
                    value: log.departmentName!,
                  ),
                ],

                if (log.cellReference != null) ...[
                  const SizedBox(height: 12),
                  _buildDetailRow(
                    icon: Icons.grid_on_rounded,
                    label: 'Cell Reference',
                    value: log.cellReference!,
                  ),
                ],

                // Changes section
                if (log.oldValue != null || log.newValue != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Changes Made',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      if (log.oldValue != null)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF2F2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: _kRed.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.remove_circle_outline,
                                        size: 14, color: _kRed),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Previous Value',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _kRed,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatValue(log.oldValue),
                                  style: TextStyle(
                                      fontSize: 13, color: _textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (log.oldValue != null && log.newValue != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Icon(Icons.arrow_forward_rounded,
                              size: 20, color: _kGray),
                        ),
                      if (log.newValue != null)
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0FDF4),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: _kGreen.withValues(alpha: 0.2)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.add_circle_outline,
                                        size: 14, color: _kGreen),
                                    const SizedBox(width: 6),
                                    Text(
                                      'New Value',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: _kGreen,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _formatValue(log.newValue),
                                  style: TextStyle(
                                      fontSize: 13, color: _textPrimary),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    String? extra,
  }) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _surfaceAltColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _textSecondary),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: _textSecondary),
          ),
        ),
        Expanded(
          child: Text(
            value + (extra ?? ''),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  IconData _getActionIcon(String action) {
    switch (action.toUpperCase()) {
      case 'LOGIN':
        return Icons.login_rounded;
      case 'LOGOUT':
        return Icons.logout_rounded;
      case 'CREATE':
        return Icons.add_circle_outline_rounded;
      case 'UPDATE':
        return Icons.edit_outlined;
      case 'DELETE':
        return Icons.delete_outline_rounded;
      case 'EXPORT':
        return Icons.download_rounded;
      default:
        return Icons.info_outline_rounded;
    }
  }

  // ════════════════════════════════════════════
  //  Table Footer (Pagination)
  // ════════════════════════════════════════════
  Widget _buildTableFooter(int totalItems, int totalPages) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items per page
          Row(
            children: [
              Text('Show',
                  style: TextStyle(fontSize: 13, color: _textSecondary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: _borderColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _itemsPerPage,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: _textPrimary),
                    items: _itemsPerPageOptions
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v')))
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
              const SizedBox(width: 8),
              Text('entries',
                  style: TextStyle(fontSize: 13, color: _textSecondary)),
              const SizedBox(width: 20),
              Text(
                'Showing ${totalItems > 0 ? (_currentPage - 1) * _itemsPerPage + 1 : 0}-${((_currentPage) * _itemsPerPage).clamp(0, totalItems)} of $totalItems',
                style: TextStyle(fontSize: 13, color: _textPrimary),
              ),
            ],
          ),

          // Page navigation
          Row(
            children: [
              _navButton(
                icon: Icons.chevron_left,
                enabled: _currentPage > 1,
                onTap: () => setState(() => _currentPage--),
              ),
              const SizedBox(width: 4),
              ..._buildPageButtons(totalPages),
              const SizedBox(width: 4),
              _navButton(
                icon: Icons.chevron_right,
                enabled: _currentPage < totalPages,
                onTap: () => setState(() => _currentPage++),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: enabled ? _surfaceAltColor : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _borderColor),
        ),
        child: Icon(icon,
            size: 18,
            color:
                enabled ? _textPrimary : _textSecondary.withValues(alpha: 0.5)),
      ),
    );
  }

  List<Widget> _buildPageButtons(int totalPages) {
    List<Widget> buttons = [];
    int start = (_currentPage - 2).clamp(1, totalPages);
    int end = (start + 4).clamp(1, totalPages);
    if (end - start < 4) start = (end - 4).clamp(1, totalPages);

    if (start > 1) {
      buttons.add(_pageButton(1));
      if (start > 2) {
        buttons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: _kGray)),
        ));
      }
    }

    for (int i = start; i <= end; i++) {
      buttons.add(_pageButton(i));
    }

    if (end < totalPages) {
      if (end < totalPages - 1) {
        buttons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: _kGray)),
        ));
      }
      buttons.add(_pageButton(totalPages));
    }

    return buttons;
  }

  Widget _pageButton(int page) {
    final isActive = page == _currentPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() => _currentPage = page),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isActive ? _kBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: isActive ? _kBlue : _borderColor),
          ),
          child: Center(
            child: Text(
              '$page',
              style: TextStyle(
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? Colors.white : _textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _selectDateRange() async {
    await showDialog(
      context: context,
      builder: (context) => _DateRangePickerDialog(
        initialStart: _startDate,
        initialEnd: _endDate,
        onApply: (start, end, label) {
          setState(() {
            _dateRangeFilter = label;
            _startDate = start;
            _endDate = end;
          });
          // Adjust end date to end of day (23:59:59) for inclusive filtering
          final adjustedEndDate = end != null
              ? DateTime(end.year, end.month, end.day, 23, 59, 59)
              : null;
          context.read<DataProvider>().loadAuditLogs(
                startDate: _startDate,
                endDate: adjustedEndDate,
              );
        },
      ),
    );
  }

  String _formatFullDate(DateTime? dt) {
    if (dt == null) return '-';
    final months = [
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
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final meridiem = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:${dt.minute.toString().padLeft(2, '0')} $meridiem';
  }

  String _formatTimestamp(DateTime? dt) {
    if (dt == null) return '-';
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

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

// ════════════════════════════════════════════════
//  Custom Modern Date Range Picker Dialog
// ════════════════════════════════════════════════
class _DateRangePickerDialog extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final void Function(DateTime? start, DateTime? end, String label) onApply;

  const _DateRangePickerDialog({
    this.initialStart,
    this.initialEnd,
    required this.onApply,
  });

  @override
  State<_DateRangePickerDialog> createState() => _DateRangePickerDialogState();
}

class _DateRangePickerDialogState extends State<_DateRangePickerDialog> {
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedPreset = '';
  late DateTime _displayMonth;

  final List<_DatePreset> _presets = [];

  @override
  void initState() {
    super.initState();
    _startDate = widget.initialStart;
    _endDate = widget.initialEnd;
    _displayMonth = DateTime.now();
    _initPresets();
  }

  void _initPresets() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    _presets.addAll([
      _DatePreset('Today', today, today),
      _DatePreset('Yesterday', today.subtract(const Duration(days: 1)),
          today.subtract(const Duration(days: 1))),
      _DatePreset(
          'Last 7 Days', today.subtract(const Duration(days: 6)), today),
      _DatePreset(
          'Last 14 Days', today.subtract(const Duration(days: 13)), today),
      _DatePreset(
          'Last 30 Days', today.subtract(const Duration(days: 29)), today),
      _DatePreset('This Month', DateTime(now.year, now.month, 1), today),
      _DatePreset('Last Month', DateTime(now.year, now.month - 1, 1),
          DateTime(now.year, now.month, 0)),
      _DatePreset('This Year', DateTime(now.year, 1, 1), today),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 560,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 30,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _kBg,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _kBlue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child:
                        Icon(Icons.date_range_rounded, color: _kBlue, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Select Date Range',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _kNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getSelectionText(),
                        style: TextStyle(fontSize: 13, color: _kGray),
                      ),
                    ],
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: _kGray),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),

            // Body
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Presets sidebar
                Container(
                  width: 160,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: _kBorder)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _presets
                        .map((preset) => _buildPresetButton(preset))
                        .toList(),
                  ),
                ),

                // Calendar section
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Month navigation
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _displayMonth = DateTime(_displayMonth.year,
                                      _displayMonth.month - 1);
                                });
                              },
                              icon: Icon(Icons.chevron_left_rounded,
                                  color: _kNavy),
                              style: IconButton.styleFrom(
                                backgroundColor: _kBg,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            Text(
                              _getMonthYearText(_displayMonth),
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _kNavy,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _displayMonth = DateTime(_displayMonth.year,
                                      _displayMonth.month + 1);
                                });
                              },
                              icon: Icon(Icons.chevron_right_rounded,
                                  color: _kNavy),
                              style: IconButton.styleFrom(
                                backgroundColor: _kBg,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Weekday headers
                        Row(
                          children:
                              ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                                  .map((day) => Expanded(
                                        child: Center(
                                          child: Text(
                                            day,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: _kGray,
                                            ),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                        ),
                        const SizedBox(height: 8),

                        // Calendar grid
                        _buildCalendarGrid(),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Clear button
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _startDate = null;
                        _endDate = null;
                        _selectedPreset = '';
                      });
                    },
                    child: Text(
                      'Clear Selection',
                      style: TextStyle(color: _kGray, fontSize: 13),
                    ),
                  ),
                  Row(
                    children: [
                      // Cancel button
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 12),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(color: _kGray, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Apply button
                      ElevatedButton(
                        onPressed: () {
                          widget.onApply(
                            _startDate,
                            _endDate,
                            _selectedPreset.isNotEmpty
                                ? _selectedPreset
                                : 'Custom',
                          );
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                        child: const Text('Apply',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetButton(_DatePreset preset) {
    final isSelected = _selectedPreset == preset.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? _kBlue.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedPreset = preset.label;
              _startDate = preset.start;
              _endDate = preset.end;
              _displayMonth = preset.start;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                if (isSelected)
                  Container(
                    width: 4,
                    height: 16,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: _kBlue,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                Text(
                  preset.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? _kBlue : _kNavy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDayOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month, 1);
    final lastDayOfMonth =
        DateTime(_displayMonth.year, _displayMonth.month + 1, 0);
    final startingWeekday = firstDayOfMonth.weekday % 7;
    final daysInMonth = lastDayOfMonth.day;
    final today = DateTime.now();

    List<Widget> rows = [];
    List<Widget> currentRow = [];

    // Add empty cells for days before the first of the month
    for (int i = 0; i < startingWeekday; i++) {
      currentRow.add(const Expanded(child: SizedBox(height: 40)));
    }

    // Add day cells
    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_displayMonth.year, _displayMonth.month, day);
      final isToday = date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
      final isStart = _startDate != null && _isSameDay(date, _startDate!);
      final isEnd = _endDate != null && _isSameDay(date, _endDate!);
      final isInRange = _startDate != null &&
          _endDate != null &&
          date.isAfter(_startDate!) &&
          date.isBefore(_endDate!);
      final isFuture = date.isAfter(today);

      currentRow.add(
        Expanded(
          child: GestureDetector(
            onTap: isFuture ? null : () => _selectDate(date),
            child: Container(
              height: 40,
              margin: const EdgeInsets.symmetric(vertical: 2),
              decoration: BoxDecoration(
                color: isStart || isEnd
                    ? _kBlue
                    : isInRange
                        ? _kBlue.withValues(alpha: 0.15)
                        : Colors.transparent,
                borderRadius: BorderRadius.horizontal(
                  left: isStart ? const Radius.circular(20) : Radius.zero,
                  right: isEnd ? const Radius.circular(20) : Radius.zero,
                ),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: isToday && !isStart && !isEnd
                      ? Border.all(color: _kBlue, width: 2)
                      : null,
                ),
                child: Center(
                  child: Text(
                    '$day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isStart || isEnd || isToday
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isFuture
                          ? _kGray.withValues(alpha: 0.4)
                          : isStart || isEnd
                              ? Colors.white
                              : _kNavy,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      if (currentRow.length == 7) {
        rows.add(Row(children: currentRow));
        currentRow = [];
      }
    }

    // Fill remaining cells
    while (currentRow.length < 7 && currentRow.isNotEmpty) {
      currentRow.add(const Expanded(child: SizedBox(height: 40)));
    }
    if (currentRow.isNotEmpty) {
      rows.add(Row(children: currentRow));
    }

    return Column(children: rows);
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedPreset = '';
      if (_startDate == null || (_startDate != null && _endDate != null)) {
        _startDate = date;
        _endDate = null;
      } else if (date.isBefore(_startDate!)) {
        _endDate = _startDate;
        _startDate = date;
      } else {
        _endDate = date;
      }
    });
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _getMonthYearText(DateTime date) {
    final months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  String _getSelectionText() {
    if (_startDate == null && _endDate == null) {
      return 'Choose a date range to filter logs';
    }
    if (_startDate != null && _endDate == null) {
      return 'Select end date...';
    }
    final months = [
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
    return '${months[_startDate!.month - 1]} ${_startDate!.day} - ${months[_endDate!.month - 1]} ${_endDate!.day}, ${_endDate!.year}';
  }
}

class _DatePreset {
  final String label;
  final DateTime start;
  final DateTime end;

  _DatePreset(this.label, this.start, this.end);
}
