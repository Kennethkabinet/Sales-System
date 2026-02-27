import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import '../config/constants.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';
import 'login_screen.dart';
import 'file_list_screen.dart';
import 'audit_history_screen.dart';
import 'edit_requests_screen.dart';
import 'sheet_screen.dart';
import 'user_management_screen.dart';
import 'settings_screen.dart';

// ─── Theme colors (Blue & Red brand palette) ───
const Color _kSidebarBg = AppColors.primaryBlue; // primary blue
const Color _kContentBg = AppColors.white; // white base

enum _LowestStockLabelMode { byName, byCode }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  int _pendingEditRequestCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadDashboard();
    });

    // Persistent admin listener — active regardless of which tab is selected.
    // Works even when the Sheets tab (SheetScreen) is unmounted.
    SocketService.instance.onAdminEditNotification = (data) {
      if (!mounted) return;
      setState(() => _pendingEditRequestCount++);
      final requester = data['requested_by'] as String? ?? 'Someone';
      final cellRef = data['cell_ref'] as String? ?? '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$requester requests edit access for cell $cellRef'),
        backgroundColor: Colors.orange[800],
        duration: const Duration(seconds: 8),
        action: SnackBarAction(
          label: 'Review',
          textColor: Colors.white,
          onPressed: () =>
              setState(() => _selectedIndex = _editRequestsTabIndex),
        ),
      ));
    };
  }

  @override
  void dispose() {
    // Remove the persistent callback so it doesn't outlive this widget.
    SocketService.instance.onAdminEditNotification = null;
    super.dispose();
  }

  /// Returns the nav index of the Edit Requests page for the current user.
  int get _editRequestsTabIndex {
    // Pages order: Dashboard(0), Sheets(1), Files(2), Audit(3), Users(4),
    // EditRequests(5), Settings(6)  — Files is always in the list for admin.
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isAdmin = auth.user?.role == 'admin';
    final isViewer = auth.user?.role == 'viewer';

    // Build pages list
    final pages = <Widget>[
      const _DashboardContent(),
      SheetScreen(
        onNavigateToEditRequests: () {
          setState(() {
            _selectedIndex = _editRequestsTabIndex;
            _pendingEditRequestCount = 0;
          });
        },
      ),
      if (!isViewer) const FileListScreen(),
      const AuditHistoryScreen(),
      if (isAdmin) const UserManagementScreen(),
      if (isAdmin) const EditRequestsScreen(),
      if (isAdmin) const SettingsScreen(),
    ];

    // Build nav items with correct indices
    final navItems = <_NavItem>[];
    navItems.add(_NavItem(Icons.dashboard, 'Admin Dashboard', 0));
    navItems.add(_NavItem(Icons.apps, 'Work Sheets', 1));
    int nextIdx = 2;
    if (!isViewer) {
      // Files page exists but we don't show it in nav per screenshot
      nextIdx++;
    }
    navItems.add(_NavItem(Icons.history, 'Audit Log', nextIdx));
    nextIdx++;
    if (isAdmin) {
      navItems.add(_NavItem(Icons.people_alt_outlined, 'Users', nextIdx));
      nextIdx++;
    }
    if (isAdmin) {
      navItems
          .add(_NavItem(Icons.lock_open_outlined, 'Edit Requests', nextIdx));
      nextIdx++;
    }
    if (isAdmin) {
      navItems.add(_NavItem(Icons.settings_outlined, 'Settings', nextIdx));
    }

    return Scaffold(
      backgroundColor: _kContentBg,
      body: Row(
        children: [
          // ── Sidebar ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _sidebarExpanded ? 220 : 68,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                right: BorderSide(color: Colors.grey.shade200, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Header: logo + brand name + hamburger
                Container(
                  height: 56,
                  padding: EdgeInsets.only(
                    left: _sidebarExpanded ? 12 : 0,
                    right: _sidebarExpanded ? 4 : 0,
                    top: 4,
                    bottom: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: _sidebarExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      // Logo
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.asset(
                            'assets/images/logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.diamond,
                              size: 22,
                              color: AppColors.primaryRed,
                            ),
                          ),
                        ),
                      ),
                      if (_sidebarExpanded) ...[
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Synergy Graphics',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryBlue,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.menu,
                              color: Colors.grey.shade600, size: 22),
                          onPressed: () => setState(
                              () => _sidebarExpanded = !_sidebarExpanded),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ] else
                        GestureDetector(
                          onTap: () => setState(
                              () => _sidebarExpanded = !_sidebarExpanded),
                          behavior: HitTestBehavior.opaque,
                          child: const SizedBox(width: 32, height: 32),
                        ),
                    ],
                  ),
                ),

                // User profile
                _buildProfile(auth),

                const SizedBox(height: 12),

                // Nav items
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: navItems.map((item) {
                      final selected = _selectedIndex == item.index;
                      return _buildNavTile(item, selected);
                    }).toList(),
                  ),
                ),

                // Logout
                _buildLogoutButton(auth),
                const SizedBox(height: 12),
              ],
            ),
          ),

          // ── Main content ──
          Expanded(
            child: Column(
              children: [
                // Top bar (only for Dashboard page – other pages have their own header)
                if (_selectedIndex == 0)
                  Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.grey.shade100),
                      ),
                    ),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _currentTitle,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF202124),
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                // Page body
                Expanded(
                  child: pages[_selectedIndex.clamp(0, pages.length - 1)],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _currentTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Work Sheets';
      default:
        return 'Dashboard';
    }
  }

  // ── Profile widget ──
  Widget _buildProfile(AuthProvider auth) {
    if (!_sidebarExpanded) {
      // Collapsed: just show avatar centered
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: Colors.grey[300],
          child: Icon(Icons.person, color: Colors.grey[600], size: 20),
        ),
      );
    }

    // Expanded: avatar + text
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.lightBlue,
            child: Icon(Icons.person, color: _kSidebarBg, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (auth.user?.fullName ?? 'ADMINISTRATOR').toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF202124),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  auth.user?.role ?? 'Administrator',
                  style: const TextStyle(
                    color: Color(0xFF5F6368),
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Nav tile ──
  Widget _buildNavTile(_NavItem item, bool selected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.hardEdge,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (item.index >= 0) {
              setState(() {
                _selectedIndex = item.index;
                // Clear badge when admin opens the Edit Requests page
                if (item.label == 'Edit Requests') {
                  _pendingEditRequestCount = 0;
                }
              });
            }
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: _sidebarExpanded ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: _sidebarExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(
                  item.icon,
                  color: selected ? _kSidebarBg : const Color(0xFF5F6368),
                  size: 20,
                ),
                if (_sidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? _kSidebarBg : const Color(0xFF5F6368),
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  // Badge for Edit Requests
                  if (item.label == 'Edit Requests' &&
                      _pendingEditRequestCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange[700],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$_pendingEditRequestCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Logout button ──
  Widget _buildLogoutButton(AuthProvider auth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Logout'),
              content: const Text('Are you sure you want to logout?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryRed,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Logout'),
                ),
              ],
            ),
          );
          if (confirmed == true) {
            await auth.logout();
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            }
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            mainAxisAlignment: _sidebarExpanded
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              const Icon(Icons.logout, color: Color(0xFF5F6368), size: 20),
              if (_sidebarExpanded) ...[
                const SizedBox(width: 12),
                const Text(
                  'Logout',
                  style: TextStyle(
                    color: Color(0xFF5F6368),
                    fontWeight: FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper model ──
class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  _NavItem(this.icon, this.label, this.index);
}

// ═══════════════════════════════════════════════════════
//  DASHBOARD CONTENT (main area)
// ═══════════════════════════════════════════════════════
class _DashboardContent extends StatefulWidget {
  const _DashboardContent();

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final _searchCtrl = TextEditingController();
  int _alertPage = 0;
  static const int _alertPageSize = 8;
  _LowestStockLabelMode _lowestStockLabelMode = _LowestStockLabelMode.byName;
  String _selectedProductStockKey = '__all__';

  // Sheet filter state
  List<Map<String, dynamic>> _sheets = [];
  Set<int> _selectedSheetIds = {}; // empty = all sheets

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = context.read<DataProvider>();
      // Load available sheets for the filter, then load dashboard
      data.loadInventorySheets().then((_) {
        if (mounted) setState(() => _sheets = data.inventorySheets);
      });
      data.loadInventoryDashboard();
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _applySheetFilter(Set<int> ids) async {
    setState(() {
      _selectedSheetIds = ids;
      _selectedProductStockKey = '__all__';
    });
    final provider = context.read<DataProvider>();
    await provider.loadInventoryDashboard(
      sheetIds: ids.isEmpty ? null : ids.toList(),
    );
  }

  String _productStockKey(Map<String, dynamic> product) {
    final name =
        (product['product_name']?.toString() ?? '').trim().toLowerCase();
    final code =
        (product['qb_code']?.toString() ?? product['qc_code']?.toString() ?? '')
            .trim()
            .toLowerCase();
    return '$name|$code';
  }

  int _selectedStockQty(InventoryDashboardData? inv) {
    final products = inv?.productStocks ?? const [];
    if (products.isEmpty) {
      final raw = inv?.summary['total_stock_qty'];
      return (raw is num) ? raw.toInt() : 0;
    }

    if (_selectedProductStockKey == '__all__') {
      return products.fold<int>(
        0,
        (sum, p) => sum + ((p['current_stock'] as num?)?.toInt() ?? 0),
      );
    }

    return products
        .where((p) => _productStockKey(p) == _selectedProductStockKey)
        .fold<int>(
            0, (sum, p) => sum + ((p['current_stock'] as num?)?.toInt() ?? 0));
  }

  Widget _buildSheetFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          )
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.filter_list_rounded,
              size: 18, color: Color(0xFF5F6368)),
          const SizedBox(width: 8),
          const Text(
            'Filter by Sheet:',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF5F6368),
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(width: 12),
          _SheetDropdown(
            sheets: _sheets,
            selectedIds: _selectedSheetIds,
            onChanged: _applySheetFilter,
          ),
          if (_selectedSheetIds.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _applySheetFilter({}),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Text(
                  'Clear',
                  style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5F6368),
                      fontWeight: FontWeight.w500),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataProvider>(
      builder: (context, data, _) {
        final inv = data.inventoryDashboardData;

        if (data.isLoading && inv == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Loading dashboard…',
                    style: TextStyle(color: Color(0xFF5F6368))),
              ],
            ),
          );
        }

        // Low-stock alert filtering + pagination
        final allAlerts = inv?.lowStockItems ?? [];
        final query = _searchCtrl.text.toLowerCase();
        final filtered = query.isEmpty
            ? allAlerts
            : allAlerts
                .where((i) => (i['product_name'] as String? ?? '')
                    .toLowerCase()
                    .contains(query))
                .toList();
        final pageCount =
            ((filtered.length) / _alertPageSize).ceil().clamp(1, 999);
        final safeAlertPage = _alertPage.clamp(0, pageCount - 1);
        final pagedAlerts = filtered
            .skip(safeAlertPage * _alertPageSize)
            .take(_alertPageSize)
            .toList();

        return RefreshIndicator(
          onRefresh: () => data.loadInventoryDashboard(
            sheetIds:
                _selectedSheetIds.isEmpty ? null : _selectedSheetIds.toList(),
          ),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Sheet filter bar ────────────────────────────────────
                if (_sheets.isNotEmpty) ...[
                  _buildSheetFilter(),
                  const SizedBox(height: 20),
                ],

                // ── Section: Summary Cards ────────────────────────────────
                _SectionTitle(title: 'Inventory Summary'),
                const SizedBox(height: 14),
                _buildStatCards(inv),
                const SizedBox(height: 28),

                // ── Section: Stock Analytics ────────────────────────────
                _SectionTitle(title: 'Stock Analytics'),
                const SizedBox(height: 14),

                // Row 2 – Stock flow + Category bar
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _DashCard(
                        title: 'Stock In vs Stock Out (Monthly)',
                        icon: Icons.compare_arrows_rounded,
                        iconColor: const Color(0xFF2E7D32),
                        child: SizedBox(
                          height: 240,
                          child: inv != null && inv.monthlyTrend.isNotEmpty
                              ? _StockInOutChart(data: inv.monthlyTrend)
                              : const _EmptyChart(
                                  message: 'No monthly data yet'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _DashCard(
                        title: 'Top 15 Lowest Stock',
                        icon: Icons.bar_chart_rounded,
                        iconColor: const Color(0xFF0277BD),
                        headerTrailing: SizedBox(
                          height: 30,
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<_LowestStockLabelMode>(
                              value: _lowestStockLabelMode,
                              borderRadius: BorderRadius.circular(8),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF5F6368),
                                fontWeight: FontWeight.w500,
                              ),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _lowestStockLabelMode = value);
                              },
                              items: const [
                                DropdownMenuItem(
                                  value: _LowestStockLabelMode.byName,
                                  child: Text('By Name'),
                                ),
                                DropdownMenuItem(
                                  value: _LowestStockLabelMode.byCode,
                                  child: Text('By QB Code'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        child: SizedBox(
                          height: 240,
                          child: inv != null && inv.lowStockItems.isNotEmpty
                              ? _LowestStockBarChart(
                                  data: (List<Map<String, dynamic>>.from(
                                    inv.lowStockItems,
                                  )..sort((a, b) {
                                          final aStock =
                                              (a['current_stock'] as num?)
                                                      ?.toDouble() ??
                                                  0.0;
                                          final bStock =
                                              (b['current_stock'] as num?)
                                                      ?.toDouble() ??
                                                  0.0;
                                          return aStock.compareTo(bStock);
                                        }))
                                      .take(15)
                                      .toList(),
                                  labelMode: _lowestStockLabelMode,
                                )
                              : const _EmptyChart(
                                  message: 'No low stock data yet'),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Row 3 – Expanded monthly usage trend
                _DashCard(
                  title: 'Monthly Usage Trend',
                  icon: Icons.trending_up_rounded,
                  iconColor: AppColors.primaryBlue,
                  child: SizedBox(
                    height: 300,
                    child: inv != null && inv.monthlyTrend.isNotEmpty
                        ? _MonthlyUsageChart(data: inv.monthlyTrend)
                        : const _EmptyChart(message: 'No monthly data yet'),
                  ),
                ),
                const SizedBox(height: 28),

                // ── Section: Low Stock Alerts ───────────────────────────
                _SectionTitle(title: 'Low Stock Alerts'),
                const SizedBox(height: 14),
                _DashCard(
                  title: '',
                  showHeader: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Alert badge row
                      if (inv != null)
                        Row(
                          children: [
                            _AlertBadge(
                              label: 'Out of Stock',
                              count: inv.summary['out_of_stock_count'] ?? 0,
                              color: Colors.red[700]!,
                            ),
                            const SizedBox(width: 10),
                            _AlertBadge(
                              label: 'Low Stock',
                              count: inv.summary['low_stock_count'] ?? 0,
                              color: Colors.orange[700]!,
                            ),
                            const Spacer(),
                            // Search
                            SizedBox(
                              width: 280,
                              child: TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Search materials…',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide:
                                        BorderSide(color: Colors.grey.shade300),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    borderSide: const BorderSide(
                                        color: AppColors.primaryBlue,
                                        width: 1.5),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  isDense: true,
                                ),
                                onChanged: (_) =>
                                    setState(() => _alertPage = 0),
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),

                      // Table
                      _LowStockTable(items: pagedAlerts),
                      const SizedBox(height: 12),

                      // Pagination
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            '${filtered.length} item(s)  •  Page ${safeAlertPage + 1} of $pageCount',
                            style: const TextStyle(
                                fontSize: 12, color: Color(0xFF5F6368)),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: const Icon(Icons.chevron_left, size: 20),
                            visualDensity: VisualDensity.compact,
                            onPressed: safeAlertPage > 0
                                ? () => setState(
                                    () => _alertPage = safeAlertPage - 1)
                                : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right, size: 20),
                            visualDensity: VisualDensity.compact,
                            onPressed: safeAlertPage < pageCount - 1
                                ? () => setState(
                                    () => _alertPage = safeAlertPage + 1)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── 6 Summary stat cards ───────────────────────────────────────────
  Widget _buildStatCards(InventoryDashboardData? inv) {
    final s = inv?.summary ?? {};
    final totalCategories = (s['total_product_categories'] as num?)?.toInt() ??
        inv?.categoryBreakdown.length ??
        0;
    final totalStockQty = _selectedStockQty(inv);
    final cards = [
      _StatCardData(
        title: 'Total Product Category',
        value: '$totalCategories',
        icon: Icons.inventory_2_outlined,
        color: AppColors.primaryBlue,
        bgColor: AppColors.lightBlue,
      ),
      _StatCardData(
        title: 'Total Stock Qty',
        value: _fmt(totalStockQty),
        icon: Icons.stacked_bar_chart_rounded,
        color: const Color(0xFF0277BD),
        bgColor: const Color(0xFFE1F5FE),
        compactControl: inv != null && inv.productStocks.isNotEmpty
            ? Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedProductStockKey,
                    isDense: true,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(8),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF5F6368),
                      fontWeight: FontWeight.w500,
                    ),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _selectedProductStockKey = value);
                    },
                    items: [
                      const DropdownMenuItem<String>(
                        value: '__all__',
                        child: Text('All Products'),
                      ),
                      ...inv.productStocks.map((p) {
                        final name = p['product_name']?.toString() ?? '-';
                        final code = p['qb_code']?.toString() ??
                            p['qc_code']?.toString() ??
                            '';
                        return DropdownMenuItem<String>(
                          value: _productStockKey(p),
                          child: Text(
                            code.isEmpty ? name : '$name ($code)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              )
            : null,
      ),
      _StatCardData(
        title: 'Low Stock Items',
        value: '${s['low_stock_count'] ?? 0}',
        icon: Icons.warning_amber_rounded,
        color: Colors.orange[800]!,
        bgColor: Colors.orange[50]!,
        highlight: (s['low_stock_count'] ?? 0) > 0,
      ),
      _StatCardData(
        title: 'Out of Stock',
        value: '${s['out_of_stock_count'] ?? 0}',
        icon: Icons.remove_shopping_cart_outlined,
        color: const Color(0xFFC62828),
        bgColor: AppColors.lightRed,
        highlight: (s['out_of_stock_count'] ?? 0) > 0,
      ),
      _StatCardData(
        title: 'Purchases This Month',
        value: _fmt(s['total_purchases_this_month'] ?? 0),
        icon: Icons.add_shopping_cart_outlined,
        color: const Color(0xFF2E7D32),
        bgColor: const Color(0xFFE8F5E9),
      ),
      _StatCardData(
        title: 'Used This Month',
        value: _fmt(s['total_used_this_month'] ?? 0),
        icon: Icons.output_rounded,
        color: const Color(0xFF6A1B9A),
        bgColor: const Color(0xFFF3E5F5),
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      final cardW = (constraints.maxWidth - 5 * 12) / 6;
      return Row(
        children: cards.asMap().entries.map((e) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (e.key > 0) const SizedBox(width: 12),
              _StatCard(data: e.value, width: cardW),
            ],
          );
        }).toList(),
      );
    });
  }

  String _fmt(dynamic n) {
    final v = n is int ? n : (n is double ? n.toInt() : 0);
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return '$v';
  }
}

// ── Section title ──────────────────────────────────────────────────────────────
class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: AppColors.primaryBlue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: Color(0xFF202124),
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }
}

// ── Stat card data model ───────────────────────────────────────────────────────
class _StatCardData {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final Color bgColor;
  final bool highlight;
  final Widget? compactControl;

  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.highlight = false,
    this.compactControl,
  });
}

// ── Stat card widget ───────────────────────────────────────────────────────────
class _StatCard extends StatefulWidget {
  final _StatCardData data;
  final double width;
  const _StatCard({required this.data, required this.width});

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: widget.width,
        height: 172,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade200, width: 0.9),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? d.color.withOpacity(0.15)
                  : Colors.black.withOpacity(0.04),
              blurRadius: _hovered ? 18 : 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.max,
            children: [
              // Accent top stripe (always present, color varies)
              Container(
                height: 3,
                color: d.color,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: d.bgColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(d.icon, color: d.color, size: 20),
                          ),
                          if (d.highlight) ...[
                            const Spacer(),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: d.color.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, size: 6, color: d.color),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Alert',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: d.color),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (d.compactControl != null) ...[
                        const SizedBox(height: 8),
                        d.compactControl!,
                      ],
                      const Spacer(),
                      Text(
                        d.value,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w800,
                          color: d.color,
                          letterSpacing: -0.5,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        d.title,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF5F6368),
                          letterSpacing: 0.1,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashboard card container ───────────────────────────────────────────────────
class _DashCard extends StatelessWidget {
  final String title;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;
  final bool showHeader;
  final Widget? headerTrailing;

  const _DashCard({
    required this.title,
    required this.child,
    this.icon,
    this.iconColor,
    this.showHeader = true,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200, width: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color:
                          (iconColor ?? AppColors.primaryBlue).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon,
                        size: 16, color: iconColor ?? AppColors.primaryBlue),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF202124),
                    letterSpacing: 0.1,
                  ),
                ),
                if (headerTrailing != null) ...[
                  const Spacer(),
                  headerTrailing!,
                ],
              ],
            ),
            const SizedBox(height: 16),
          ],
          child,
        ],
      ),
    );
  }
}

// ── Empty chart placeholder ────────────────────────────────────────────────────
class _EmptyChart extends StatelessWidget {
  final String message;
  const _EmptyChart({this.message = 'No data available'});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.bar_chart_outlined, size: 40, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
        ],
      ),
    );
  }
}

// ── Monthly Usage Trend – Line Chart ──────────────────────────────────────────
class _MonthlyUsageChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _MonthlyUsageChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((e) {
      final val = (e.value['stock_out'] as num?)?.toDouble() ?? 0.0;
      return FlSpot(e.key.toDouble(), val);
    }).toList();

    final maxY = spots.isEmpty
        ? 10.0
        : (spots.map((s) => s.y).reduce((a, b) => a > b ? a : b) * 1.2)
            .clamp(10.0, double.infinity);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade100, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    data[i]['month_label']?.toString() ?? '',
                    style:
                        const TextStyle(fontSize: 9, color: Color(0xFF9E9E9E)),
                  ),
                );
              },
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: AppColors.primaryBlue,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (s, _, __, ___) => FlDotCirclePainter(
                radius: 3,
                color: AppColors.primaryBlue,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: AppColors.primaryBlue.withOpacity(0.08),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipBgColor: const Color(0xFF1565C0),
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      'Used: ${s.y.toInt()}',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }
}

// ── Top 15 Lowest Stock – Bar Chart ───────────────────────────────────────────
class _LowestStockBarChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final _LowestStockLabelMode labelMode;
  const _LowestStockBarChart({required this.data, required this.labelMode});

  static const _colors = [
    Color(0xFF1565C0),
    Color(0xFF0097A7),
    Color(0xFF2E7D32),
    Color(0xFF6A1B9A),
    Color(0xFFBF360C),
  ];

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _EmptyChart();

    final maxY = data
            .map((d) => (d['current_stock'] as num?)?.toDouble() ?? 0.0)
            .reduce((a, b) => a > b ? a : b) *
        1.25;

    final groups = data.asMap().entries.map((e) {
      final stock = (e.value['current_stock'] as num?)?.toDouble() ?? 0.0;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: stock,
            width: 12,
            color: _colors[e.key % _colors.length],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ],
      );
    }).toList();

    return BarChart(
      BarChartData(
        maxY: maxY.clamp(10.0, double.infinity),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) =>
              FlLine(color: Colors.grey.shade100, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= data.length) return const SizedBox();
                final item = data[i];
                final code = item['qb_code']?.toString() ??
                    item['qc_code']?.toString() ??
                    item['code']?.toString() ??
                    '-';
                final name = item['product_name']?.toString() ?? '-';
                final label =
                    labelMode == _LowestStockLabelMode.byCode ? code : name;
                final shortLabel =
                    label.length > 10 ? '${label.substring(0, 10)}…' : label;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    shortLabel,
                    style:
                        const TextStyle(fontSize: 9, color: Color(0xFF5F6368)),
                  ),
                );
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              getTitlesWidget: (v, _) => Text(
                v.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
              ),
            ),
          ),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        barGroups: groups,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: const Color(0xFF202124),
            getTooltipItem: (group, _, rod, __) {
              final item = data[group.x];
              final code = item['qb_code']?.toString() ??
                  item['qc_code']?.toString() ??
                  item['code']?.toString() ??
                  '-';
              final name = item['product_name']?.toString() ?? '-';
              final label =
                  labelMode == _LowestStockLabelMode.byCode ? code : name;
              return BarTooltipItem(
                '$label\n${rod.toY.toInt()} units',
                const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── Ink Consumption – Pie Chart ────────────────────────────────────────────────
class _InkPieChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  const _InkPieChart({required this.data});

  @override
  State<_InkPieChart> createState() => _InkPieChartState();
}

class _InkPieChartState extends State<_InkPieChart> {
  int _touchedIndex = -1;

  static Color _inkColor(String type) {
    switch (type.toLowerCase()) {
      case 'cyan':
        return const Color(0xFF00BCD4);
      case 'magenta':
        return const Color(0xFFE91E63);
      case 'yellow':
        return const Color(0xFFFFC107);
      case 'black':
        return const Color(0xFF37474F);
      default:
        return const Color(0xFF78909C);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.data.fold<double>(
        0, (s, e) => s + ((e['total_used'] as num?)?.toDouble() ?? 0));

    return Row(
      children: [
        Expanded(
          flex: 3,
          child: PieChart(
            PieChartData(
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response == null ||
                      response.touchedSection == null) {
                    setState(() => _touchedIndex = -1);
                    return;
                  }
                  setState(() => _touchedIndex =
                      response.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: widget.data.asMap().entries.map((e) {
                final isTouched = e.key == _touchedIndex;
                final val = (e.value['total_used'] as num?)?.toDouble() ?? 0.0;
                final pct =
                    total > 0 ? (val / total * 100).toStringAsFixed(1) : '0';
                return PieChartSectionData(
                  value: val,
                  title: '$pct%',
                  color: _inkColor(e.value['ink_type']?.toString() ?? ''),
                  radius: isTouched ? 78 : 68,
                  titleStyle: TextStyle(
                    fontSize: isTouched ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                );
              }).toList(),
              sectionsSpace: 2,
              centerSpaceRadius: 30,
            ),
          ),
        ),
        // Legend
        Expanded(
          flex: 2,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: widget.data.map((e) {
              final ink = e['ink_type']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _inkColor(ink),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$ink\n${e['total_used']} units',
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF5F6368)),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ── Stock In vs Out – Grouped Bar Chart ───────────────────────────────────────
class _StockInOutChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _StockInOutChart({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const _EmptyChart();

    double maxY = 10.0;
    for (final d in data) {
      final inn = (d['stock_in'] as num?)?.toDouble() ?? 0.0;
      final out = (d['stock_out'] as num?)?.toDouble() ?? 0.0;
      if (inn > maxY) maxY = inn;
      if (out > maxY) maxY = out;
    }
    maxY *= 1.25;

    final groups = data.asMap().entries.map((e) {
      final inn = (e.value['stock_in'] as num?)?.toDouble() ?? 0.0;
      final out = (e.value['stock_out'] as num?)?.toDouble() ?? 0.0;
      return BarChartGroupData(
        x: e.key,
        groupVertically: false,
        barRods: [
          BarChartRodData(
            toY: inn,
            width: 10,
            color: const Color(0xFF2E7D32),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
          BarChartRodData(
            toY: out,
            width: 10,
            color: AppColors.primaryRed,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ],
        barsSpace: 2,
      );
    }).toList();

    return Column(
      children: [
        // Legend
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _LegendDot(color: const Color(0xFF2E7D32), label: 'Stock In'),
            const SizedBox(width: 12),
            _LegendDot(color: AppColors.primaryRed, label: 'Stock Out'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: BarChart(
            BarChartData(
              maxY: maxY,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (v) =>
                    FlLine(color: Colors.grey.shade100, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length) return const SizedBox();
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          data[i]['month_label']?.toString() ?? '',
                          style: const TextStyle(
                              fontSize: 9, color: Color(0xFF9E9E9E)),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 38,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF9E9E9E)),
                    ),
                  ),
                ),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: groups,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  tooltipBgColor: const Color(0xFF202124),
                  getTooltipItem: (group, _, rod, rodIndex) {
                    final label = rodIndex == 0 ? 'In' : 'Out';
                    return BarTooltipItem(
                      '${data[group.x]['month_label']} $label\n'
                      '${rod.toY.toInt()} units',
                      const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Legend dot helper ──────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF5F6368))),
      ],
    );
  }
}

// Returns a display name for a sheet, appending a short date when the name
// is shared by more than one sheet in the list.
String _sheetDisplayName(
    Map<String, dynamic> sheet, List<Map<String, dynamic>> allSheets) {
  final name = sheet['name'] as String? ?? 'Sheet ${sheet['id']}';
  final duplicates =
      allSheets.where((s) => (s['name'] as String?) == name).length;
  if (duplicates <= 1) return name;
  // Append a short date from created_at to disambiguate
  final raw = sheet['created_at'];
  if (raw == null) return '$name (#${sheet['id']})';
  try {
    final dt = DateTime.parse(raw.toString()).toLocal();
    final mon = const [
      '',
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
    ][dt.month];
    return '$name ($mon ${dt.day})';
  } catch (_) {
    return '$name (#${sheet['id']})';
  }
}

// ── Sheet dropdown filter ──────────────────────────────────────────────────────
class _SheetDropdown extends StatefulWidget {
  final List<Map<String, dynamic>> sheets;
  final Set<int> selectedIds;
  final ValueChanged<Set<int>> onChanged;

  const _SheetDropdown({
    required this.sheets,
    required this.selectedIds,
    required this.onChanged,
  });

  @override
  State<_SheetDropdown> createState() => _SheetDropdownState();
}

class _SheetDropdownState extends State<_SheetDropdown> {
  final LayerLink _layerLink = LayerLink();
  final TextEditingController _searchCtrl = TextEditingController();
  OverlayEntry? _overlay;
  bool _isOpen = false;

  @override
  void dispose() {
    _closeDropdown();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggleDropdown() => _isOpen ? _closeDropdown() : _openDropdown();

  void _openDropdown() {
    _searchCtrl.clear();
    _overlay = _buildOverlay();
    Overlay.of(context).insert(_overlay!);
    setState(() => _isOpen = true);
  }

  void _closeDropdown() {
    _overlay?.remove();
    _overlay = null;
    if (mounted) setState(() => _isOpen = false);
  }

  OverlayEntry _buildOverlay() {
    return OverlayEntry(
      builder: (_) => _SheetDropdownOverlay(
        layerLink: _layerLink,
        sheets: widget.sheets,
        selectedIds: widget.selectedIds,
        searchCtrl: _searchCtrl,
        onChanged: (ids) {
          widget.onChanged(ids);
          _overlay?.markNeedsBuild();
          if (mounted) setState(() {});
        },
        onClose: _closeDropdown,
      ),
    );
  }

  String get _label {
    if (widget.selectedIds.isEmpty) return 'All Sheets';
    if (widget.selectedIds.length == 1) {
      final id = widget.selectedIds.first;
      final s = widget.sheets.firstWhere(
        (e) =>
            (e['id'] is int ? e['id'] : int.tryParse(e['id'].toString())) == id,
        orElse: () => <String, dynamic>{'name': 'Sheet $id'},
      );
      return _sheetDisplayName(s, widget.sheets);
    }
    return '${widget.selectedIds.length} Sheets Selected';
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleDropdown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(
              color: _isOpen ? AppColors.primaryBlue : Colors.grey.shade300,
              width: _isOpen ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isOpen
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.layers_outlined,
                size: 15,
                color:
                    _isOpen ? AppColors.primaryBlue : const Color(0xFF5F6368),
              ),
              const SizedBox(width: 7),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 80, maxWidth: 220),
                child: Text(
                  _label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _isOpen
                        ? AppColors.primaryBlue
                        : const Color(0xFF202124),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              AnimatedRotation(
                turns: _isOpen ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color:
                      _isOpen ? AppColors.primaryBlue : const Color(0xFF5F6368),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Overlay panel ─────────────────────────────────────────────────────────────────
class _SheetDropdownOverlay extends StatefulWidget {
  final LayerLink layerLink;
  final List<Map<String, dynamic>> sheets;
  final Set<int> selectedIds;
  final TextEditingController searchCtrl;
  final ValueChanged<Set<int>> onChanged;
  final VoidCallback onClose;

  const _SheetDropdownOverlay({
    required this.layerLink,
    required this.sheets,
    required this.selectedIds,
    required this.searchCtrl,
    required this.onChanged,
    required this.onClose,
  });

  @override
  State<_SheetDropdownOverlay> createState() => _SheetDropdownOverlayState();
}

class _SheetDropdownOverlayState extends State<_SheetDropdownOverlay> {
  late Set<int> _local;
  static const double _itemH = 40;
  static const int _maxVisible = 7;

  @override
  void initState() {
    super.initState();
    _local = Set<int>.from(widget.selectedIds);
    widget.searchCtrl.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    widget.searchCtrl.removeListener(_rebuild);
    super.dispose();
  }

  int _idOf(Map<String, dynamic> s) =>
      s['id'] is int ? s['id'] as int : int.tryParse(s['id'].toString()) ?? 0;

  List<Map<String, dynamic>> get _filtered {
    final q = widget.searchCtrl.text.toLowerCase();
    if (q.isEmpty) return widget.sheets;
    return widget.sheets
        .where((s) => (s['name'] as String? ?? '').toLowerCase().contains(q))
        .toList();
  }

  void _toggle(int id) {
    setState(() {
      if (id == -1) {
        _local.clear();
      } else {
        _local.contains(id) ? _local.remove(id) : _local.add(id);
      }
    });
    widget.onChanged(Set<int>.from(_local));
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    final listH = (filtered.length.clamp(1, _maxVisible) * _itemH);

    return Stack(
      children: [
        // Tap-outside-to-dismiss
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            behavior: HitTestBehavior.translucent,
            child: const SizedBox.expand(),
          ),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          targetAnchor: Alignment.bottomLeft,
          followerAnchor: Alignment.topLeft,
          offset: const Offset(0, 4),
          showWhenUnlinked: false,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 280,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Search input
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                    child: TextField(
                      controller: widget.searchCtrl,
                      autofocus: true,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search sheet...',
                        hintStyle: const TextStyle(
                            fontSize: 13, color: Color(0xFFBBBBBB)),
                        prefixIcon: const Icon(Icons.search, size: 17),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(
                              color: AppColors.primaryBlue, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: Colors.grey.shade100),
                  // "All Sheets" row
                  _DropdownItem(
                    label: 'All Sheets',
                    selected: _local.isEmpty,
                    isAll: true,
                    onTap: () => _toggle(-1),
                  ),
                  Divider(height: 1, color: Colors.grey.shade100),
                  // Scrollable sheet list
                  SizedBox(
                    height: listH,
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text('No sheets found',
                                style: TextStyle(
                                    fontSize: 12, color: Color(0xFF9E9E9E))),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              final id = _idOf(s);
                              return _DropdownItem(
                                label: _sheetDisplayName(s, widget.sheets),
                                selected: _local.contains(id),
                                onTap: () => _toggle(id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// Single row item inside the dropdown
class _DropdownItem extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isAll;

  const _DropdownItem({
    required this.label,
    required this.selected,
    required this.onTap,
    this.isAll = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: selected
            ? AppColors.primaryBlue.withOpacity(0.06)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              selected
                  ? (isAll ? Icons.done_all_rounded : Icons.check_box_rounded)
                  : (isAll
                      ? Icons.layers_outlined
                      : Icons.check_box_outline_blank_rounded),
              size: 17,
              color: selected ? AppColors.primaryBlue : const Color(0xFFBDBDBD),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected
                      ? AppColors.primaryBlue
                      : const Color(0xFF202124),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Alert badge ────────────────────────────────────────────────────────────────
class _AlertBadge extends StatelessWidget {
  final String label;
  final dynamic count;
  final Color color;
  const _AlertBadge(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    final n = count is int ? count : (count as num).toInt();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 10,
            backgroundColor: color,
            child: Text(
              '$n',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}

// ── Low Stock Alert Table ──────────────────────────────────────────────────────
class _LowStockTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  const _LowStockTable({required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 36, color: Colors.green.shade400),
              const SizedBox(height: 8),
              const Text('All materials are sufficiently stocked',
                  style: TextStyle(color: Color(0xFF5F6368), fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: Colors.grey.shade100, width: 1),
          ),
          columnWidths: const {
            0: FlexColumnWidth(3.1),
            1: FlexColumnWidth(1.2),
            2: FlexColumnWidth(1.2),
            3: FlexColumnWidth(1.1),
            4: FlexColumnWidth(1.5),
          },
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFF6F8FB)),
              children: const [
                _TH('Material Name'),
                _TH('Curr. Stock'),
                _TH('Min. Level'),
                _TH('Critical'),
                _TH('Status'),
              ],
            ),
            ...items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final status = item['stock_status']?.toString() ?? 'ok';
              final isOut =
                  status == 'critical' && (item['current_stock'] as num?) == 0;

              final rowColor = isOut
                  ? Colors.red.shade50.withOpacity(0.45)
                  : index.isEven
                      ? Colors.white
                      : const Color(0xFFFAFBFD);

              return TableRow(
                decoration: BoxDecoration(color: rowColor),
                children: [
                  _TD(
                    child: Row(
                      children: [
                        Icon(
                          isOut ? Icons.block : Icons.warning_amber_rounded,
                          size: 15,
                          color: isOut ? Colors.red[700] : Colors.orange[700],
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item['product_name']?.toString() ?? '-',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF202124),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TD(
                    child: Text(
                      '${item['current_stock'] ?? 0}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color:
                            isOut ? Colors.red[700] : const Color(0xFFB26A00),
                      ),
                    ),
                  ),
                  _TD(
                    child: Text(
                      '${item['maintaining_qty'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5F6368),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _TD(
                    child: Text(
                      '${item['critical_qty'] ?? 0}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5F6368),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _TD(
                    child: _StatusChip(
                      status: status,
                      isOutOfStock: (item['current_stock'] as num?) == 0,
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
}

// Table header cell
class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF5F6368),
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

// Table data cell
class _TD extends StatelessWidget {
  final Widget child;
  const _TD({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: child,
    );
  }
}

// Status chip
class _StatusChip extends StatelessWidget {
  final String status;
  final bool isOutOfStock;
  const _StatusChip({required this.status, this.isOutOfStock = false});

  @override
  Widget build(BuildContext context) {
    final label = isOutOfStock
        ? 'Out of Stock'
        : status == 'critical'
            ? 'Critical'
            : 'Low Stock';
    final color = isOutOfStock || status == 'critical'
        ? Colors.red[700]!
        : Colors.orange[700]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
