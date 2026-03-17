import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import '../providers/theme_provider.dart';
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

// ─── Theme colors (Modern SaaS: soft sidebar + floating cards) ───
const Color _kSidebarBg = Colors.white; // white sidebar
const Color _kSidebarBgActive =
    Color(0xFFE8F0FE); // light blue for active state
const Color _kSidebarActiveBlue = Color(0xFF4285F4); // blue for active items
const Color _kSidebarInactiveGrey =
    Color(0xFF565658); // dark tone for inactive items
const Color _kContentBg = Color(0xFFF9FAFB); // light grey background
const Color _kHeaderOrange = Color(0xFFE44408); // orange for accents
const Color _kBorder = Color(0xFFE5E7EB); // neutral border

const List<String> _kMonthNamesShort = [
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
  'Dec',
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;
  int _pendingEditRequestCount = 0;
  final TextEditingController _headerSearchCtrl = TextEditingController();
  final FocusNode _headerSearchFocus = FocusNode();
  String? _pendingDashboardSectionId;
  int _dashboardJumpToken = 0;
  final List<String> _recentSearchLabels = [];
  List<Map<String, dynamic>> _sheetFoldersForSearch = [];
  static const int _maxRecentSearches = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = context.read<DataProvider>();
      data.loadDashboard();
      data.loadInventorySheets();
      data.loadInventoryDashboard();
    });
    _loadSheetFoldersForSearch();

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

  Future<void> _loadSheetFoldersForSearch() async {
    try {
      final response = await ApiService.getSheetFolders();
      if (!mounted) return;
      setState(() {
        _sheetFoldersForSearch = (response['folders'] as List?)
                ?.cast<Map<String, dynamic>>()
                .toList() ??
            [];
      });
    } catch (_) {
      // Search remains functional even when folder catalog cannot be loaded.
    }
  }

  @override
  void dispose() {
    // Remove the persistent callback so it doesn't outlive this widget.
    SocketService.instance.onAdminEditNotification = null;
    _headerSearchCtrl.dispose();
    _headerSearchFocus.dispose();
    super.dispose();
  }

  /// Returns the nav index of the Edit Requests page for the current user.
  int get _editRequestsTabIndex {
    // Pages order: Dashboard(0), Sheets(1), Files(2), Audit(3), Users(4),
    // EditRequests(5), Settings(6)  — Files is always in the list for admin.
    return 5;
  }

  List<_GlobalSearchTarget> _buildSearchTargets({
    required bool isAdmin,
    required int auditIndex,
    required DataProvider data,
  }) {
    final targets = <_GlobalSearchTarget>[
      _GlobalSearchTarget(
        label: 'Dashboard',
        subtitle: 'Overview and system metrics',
        tabIndex: 0,
        icon: Icons.dashboard,
        keywords: const ['home', 'overview', 'dashboard'],
      ),
      _GlobalSearchTarget(
        label: 'Inventory Summary',
        subtitle: 'Dashboard section',
        tabIndex: 0,
        dashboardSectionId: 'inventory_summary',
        icon: Icons.inventory_2_outlined,
        keywords: const [
          'inventory',
          'inven',
          'summary',
          'stock summary',
          'total stock',
        ],
      ),
      _GlobalSearchTarget(
        label: 'Stock Analytics',
        subtitle: 'Dashboard section',
        tabIndex: 0,
        dashboardSectionId: 'stock_analytics',
        icon: Icons.analytics_outlined,
        keywords: const ['analytics', 'stock flow', 'stock in', 'stock out'],
      ),
      _GlobalSearchTarget(
        label: 'Monthly Usage Trend',
        subtitle: 'Dashboard chart',
        tabIndex: 0,
        dashboardSectionId: 'monthly_usage',
        icon: Icons.trending_up,
        keywords: const ['monthly', 'usage', 'trend', 'chart'],
      ),
      _GlobalSearchTarget(
        label: 'Low Stock Alerts',
        subtitle: 'Dashboard section',
        tabIndex: 0,
        dashboardSectionId: 'low_stock_alerts',
        icon: Icons.warning_amber_rounded,
        keywords: const ['low stock', 'alerts', 'critical stock'],
      ),
      _GlobalSearchTarget(
        label: 'Work Sheets',
        subtitle: 'Sheets and formulas',
        tabIndex: 1,
        icon: Icons.apps,
        keywords: const ['sheet', 'worksheet', 'excel', 'formula'],
      ),
      _GlobalSearchTarget(
        label: 'Audit Log',
        subtitle: 'User and system activity',
        tabIndex: auditIndex,
        icon: Icons.history,
        keywords: const ['audit', 'history', 'activity', 'logs'],
      ),
    ];

    if (isAdmin) {
      targets.addAll([
        _GlobalSearchTarget(
          label: 'Users',
          subtitle: 'User management',
          tabIndex: 4,
          icon: Icons.people_alt_outlined,
          keywords: const ['users', 'accounts', 'members'],
        ),
        _GlobalSearchTarget(
          label: 'Edit Users',
          subtitle: 'Manage and edit user accounts',
          tabIndex: 4,
          icon: Icons.edit_outlined,
          keywords: const ['edit user', 'update user', 'user permissions'],
        ),
        _GlobalSearchTarget(
          label: 'Edit Requests',
          subtitle: 'Cell edit approvals',
          tabIndex: _editRequestsTabIndex,
          icon: Icons.lock_open_outlined,
          keywords: const ['request', 'approval', 'edit request'],
        ),
        _GlobalSearchTarget(
          label: 'Settings',
          subtitle: 'System settings',
          tabIndex: 6,
          icon: Icons.settings_outlined,
          keywords: const [
            'settings',
            'system',
            'preferences',
            'configuration',
          ],
        ),
      ]);
    }

    final sheetTargets = data.inventorySheets
        .map((sheet) {
          final name =
              (sheet['name'] ?? sheet['sheet_name'] ?? '').toString().trim();
          if (name.isEmpty) return null;
          return _GlobalSearchTarget(
            label: 'Sheet: $name',
            subtitle: 'Work Sheets',
            tabIndex: 1,
            icon: Icons.table_chart_outlined,
            keywords: [name, 'sheet', 'worksheet'],
          );
        })
        .whereType<_GlobalSearchTarget>()
        .take(30)
        .toList();

    final folderTargets = _sheetFoldersForSearch
        .map((folder) {
          final name = (folder['name'] ?? '').toString().trim();
          if (name.isEmpty) return null;
          return _GlobalSearchTarget(
            label: 'Folder: $name',
            subtitle: 'Work Sheets folder',
            tabIndex: 1,
            icon: Icons.folder_outlined,
            keywords: [name, 'folder', 'sheet folder'],
          );
        })
        .whereType<_GlobalSearchTarget>()
        .take(30)
        .toList();

    targets.addAll(sheetTargets);
    targets.addAll(folderTargets);

    final seen = <String>{};
    final deduped = <_GlobalSearchTarget>[];
    for (final target in targets) {
      final key =
          '${target.label.toLowerCase()}|${target.subtitle.toLowerCase()}';
      if (seen.add(key)) {
        deduped.add(target);
      }
    }

    return deduped;
  }

  List<_GlobalSearchTarget> _searchMatches(
    String query,
    List<_GlobalSearchTarget> targets,
  ) {
    final q = query.trim().toLowerCase();
    final recentTargets = _resolveRecentTargets(targets);
    if (q.isEmpty) {
      final fallback = targets
          .where((t) => !recentTargets.any((r) => r.label == t.label))
          .take(8)
          .toList();
      return [...recentTargets, ...fallback];
    }

    final scored = <({int score, _GlobalSearchTarget target})>[];
    for (final target in targets) {
      final label = target.label.toLowerCase();
      final subtitle = target.subtitle.toLowerCase();
      final keywordText = target.keywords.join(' ').toLowerCase();

      int score = 0;
      if (label == q) score += 100;
      if (label.startsWith(q)) score += 70;
      if (label.contains(q)) score += 50;
      if (keywordText.startsWith(q)) score += 45;
      if (keywordText.contains(q)) score += 35;
      if (subtitle.contains(q)) score += 20;

      if (score > 0) {
        scored.add((score: score, target: target));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    final ranked = scored.map((entry) => entry.target).toList();
    final recentMatches = recentTargets
        .where((recent) => ranked.any((item) => item.label == recent.label))
        .toList();
    final others =
        ranked.where((item) => !recentMatches.contains(item)).toList();
    return [...recentMatches, ...others];
  }

  List<_GlobalSearchTarget> _resolveRecentTargets(
    List<_GlobalSearchTarget> targets,
  ) {
    if (_recentSearchLabels.isEmpty) return const [];
    final byLabel = {for (final t in targets) t.label: t};
    return _recentSearchLabels
        .map((label) => byLabel[label])
        .whereType<_GlobalSearchTarget>()
        .toList();
  }

  void _rememberSearch(_GlobalSearchTarget target) {
    setState(() {
      _recentSearchLabels.remove(target.label);
      _recentSearchLabels.insert(0, target.label);
      if (_recentSearchLabels.length > _maxRecentSearches) {
        _recentSearchLabels.removeRange(
            _maxRecentSearches, _recentSearchLabels.length);
      }
    });
  }

  void _goToSearchTarget(_GlobalSearchTarget target) {
    _rememberSearch(target);
    _headerSearchCtrl.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _selectedIndex = target.tabIndex;
      if (target.tabIndex == _editRequestsTabIndex) {
        _pendingEditRequestCount = 0;
      }
      if (target.tabIndex == 0 && target.dashboardSectionId != null) {
        _pendingDashboardSectionId = target.dashboardSectionId;
        _dashboardJumpToken++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final data = Provider.of<DataProvider>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF111827) : _kContentBg;
    final sidebarBg = isDark ? const Color(0xFF1F2937) : _kSidebarBg;
    final borderColor = isDark ? const Color(0xFF374151) : _kBorder;
    final mutedText =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final isAdmin = auth.user?.role == 'admin';
    final isViewer = auth.user?.role == 'viewer';

    // Build pages list
    final pages = <Widget>[
      _DashboardContent(
        jumpToSectionId: _pendingDashboardSectionId,
        jumpToSectionToken: _dashboardJumpToken,
      ),
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

    // Build grouped nav items with correct page indices.
    // Pages order remains: Dashboard(0), Sheets(1), Files(2, hidden in nav),
    // Audit, Users(admin), Edit Requests(admin), Settings(admin)
    final mainNavItems = <_NavItem>[
      _NavItem(Icons.dashboard, 'Dashboard', 0),
      _NavItem(Icons.apps, 'Work Sheets', 1),
    ];

    int nextIdx = 2;
    if (!isViewer) {
      // Files page exists but is intentionally hidden from sidebar nav.
      nextIdx++;
    }
    final auditIndex = nextIdx;

    final managementNavItems = <_NavItem>[];
    if (isAdmin) {
      managementNavItems.add(_NavItem(Icons.people_alt_outlined, 'Users', 4));
      managementNavItems
          .add(_NavItem(Icons.lock_open_outlined, 'Edit Requests', 5));
    }
    managementNavItems.add(_NavItem(Icons.history, 'Audit Log', auditIndex));

    final systemNavItems = <_NavItem>[];
    if (isAdmin) {
      systemNavItems.add(_NavItem(Icons.settings_outlined, 'Settings', 6));
    }

    final searchTargets = _buildSearchTargets(
      isAdmin: isAdmin,
      auditIndex: auditIndex,
      data: data,
    );

    return Scaffold(
      backgroundColor: pageBg,
      body: Row(
        children: [
          // ── Sidebar ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _sidebarExpanded ? 220 : 68,
            clipBehavior: Clip.hardEdge,
            decoration: BoxDecoration(
              color: sidebarBg,
              border: Border(
                right: BorderSide(color: borderColor, width: 1),
              ),
            ),
            child: Column(
              children: [
                // Header: logo + brand name + hamburger
                Container(
                  height: 64,
                  padding: EdgeInsets.only(
                    left: _sidebarExpanded ? 8 : 0,
                    right: _sidebarExpanded ? 8 : 0,
                    top: 4,
                    bottom: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: _sidebarExpanded
                        ? MainAxisAlignment.start
                        : MainAxisAlignment.center,
                    children: [
                      if (_sidebarExpanded) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 12),
                          child: IconButton(
                            icon: Icon(Icons.menu, color: mutedText, size: 22),
                            onPressed: () =>
                                setState(() => _sidebarExpanded = false),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 32, minHeight: 32),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: 182,
                              height: 46,
                              child: Image.asset(
                                isDark
                                    ? 'assets/images/logo_combined_dark.png'
                                    : 'assets/images/logo_combined.png',
                                fit: BoxFit.contain,
                                alignment: Alignment.center,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.diamond,
                                  size: 18,
                                  color: AppColors.primaryOrange,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 44),
                      ] else
                        IconButton(
                          icon: Icon(Icons.menu, color: mutedText, size: 22),
                          onPressed: () => setState(
                              () => _sidebarExpanded = !_sidebarExpanded),
                          padding: EdgeInsets.zero,
                          constraints:
                              const BoxConstraints(minWidth: 32, minHeight: 32),
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
                    primary: false,
                    padding: EdgeInsets.zero,
                    children: [
                      if (_sidebarExpanded) _buildNavSectionHeader('MAIN'),
                      ...mainNavItems.map((item) {
                        final selected = _selectedIndex == item.index;
                        return _buildNavTile(item, selected);
                      }),
                      if (_sidebarExpanded)
                        _buildNavSectionHeader('MANAGEMENT'),
                      ...managementNavItems.map((item) {
                        final selected = _selectedIndex == item.index;
                        return _buildNavTile(item, selected);
                      }),
                      if (_sidebarExpanded && systemNavItems.isNotEmpty)
                        _buildNavSectionHeader('SYSTEM'),
                      ...systemNavItems.map((item) {
                        final selected = _selectedIndex == item.index;
                        return _buildNavTile(item, selected);
                      }),
                    ],
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
                // Top bar (floating card)
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                  color: pageBg,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1F2937) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderColor),
                    ),
                    child: Row(
                      children: [
                        Text(
                          _currentTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: isDark
                                ? const Color(0xFFF3F4F6)
                                : const Color(0xFF1F2937),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 320,
                          height: 40,
                          decoration: BoxDecoration(
                            color:
                                isDark ? const Color(0xFF111827) : _kContentBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderColor),
                          ),
                          child: _buildHeaderSearch(
                            targets: searchTargets,
                            isDark: isDark,
                            borderColor: borderColor,
                            mutedText: mutedText,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _HeaderIconButton(
                          icon: isDark
                              ? Icons.dark_mode_outlined
                              : Icons.light_mode_outlined,
                          badge: 0,
                          onTap: () =>
                              context.read<ThemeProvider>().toggleTheme(),
                        ),
                        const SizedBox(width: 8),
                        _HeaderIconButton(
                          icon: Icons.notifications_none_outlined,
                          badge: 0,
                          onTap: () {},
                        ),
                        const SizedBox(width: 14),
                        _buildHeaderProfile(auth),
                      ],
                    ),
                  ),
                ),
                // Page body
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex.clamp(0, pages.length - 1),
                    children: pages,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderSearch({
    required List<_GlobalSearchTarget> targets,
    required bool isDark,
    required Color borderColor,
    required Color mutedText,
  }) {
    return Autocomplete<_GlobalSearchTarget>(
      optionsBuilder: (value) => _searchMatches(value.text, targets),
      displayStringForOption: (option) => option.label,
      onSelected: _goToSearchTarget,
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList();
        if (items.isEmpty) {
          return const SizedBox.shrink();
        }
        final hasQuery = _headerSearchCtrl.text.trim().isNotEmpty;
        final recentSet = _recentSearchLabels.toSet();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 10,
            borderRadius: BorderRadius.circular(12),
            color: isDark ? const Color(0xFF0F172A) : Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 300,
                minWidth: 320,
                maxWidth: 360,
              ),
              child: ListView(
                primary: false,
                padding: const EdgeInsets.symmetric(vertical: 6),
                shrinkWrap: true,
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: Text(
                      hasQuery ? 'Recommended' : 'Recent Searches',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: mutedText,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  ...items.map((item) {
                    final isRecent = recentSet.contains(item.label);
                    return InkWell(
                      onTap: () => onSelected(item),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              size: 18,
                              color: isDark
                                  ? const Color(0xFFBFDBFE)
                                  : const Color(0xFF2563EB),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? const Color(0xFFE5E7EB)
                                          : const Color(0xFF1F2937),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    item.subtitle,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: mutedText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (isRecent)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF1E293B)
                                      : const Color(0xFFEFF6FF),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0xFF334155)
                                        : const Color(0xFFBFDBFE),
                                  ),
                                ),
                                child: Text(
                                  'Recent',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF1E3A8A),
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
            ),
          ),
        );
      },
      fieldViewBuilder: (context, textCtrl, focusNode, onSubmitted) {
        if (_headerSearchCtrl.text != textCtrl.text) {
          _headerSearchCtrl.value = textCtrl.value;
        }
        return TextField(
          controller: textCtrl,
          focusNode: focusNode,
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937),
          ),
          decoration: InputDecoration(
            border: InputBorder.none,
            isDense: true,
            hintText: 'Search pages, modules, and tools',
            hintStyle: TextStyle(
              fontSize: 13,
              color: mutedText,
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 18,
              color: mutedText,
            ),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 7),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1F2937) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: borderColor),
                ),
                child: Text(
                  'Ctrl+K',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: mutedText,
                  ),
                ),
              ),
            ),
            suffixIconConstraints: const BoxConstraints(
              minWidth: 72,
              minHeight: 32,
            ),
          ),
          onChanged: (value) {
            _headerSearchCtrl.value = textCtrl.value;
          },
          onTap: () {
            if (textCtrl.text.isEmpty) {
              textCtrl.value = const TextEditingValue(
                text: ' ',
                selection: TextSelection.collapsed(offset: 1),
              );
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                textCtrl.value = const TextEditingValue(
                  text: '',
                  selection: TextSelection.collapsed(offset: 0),
                );
                _headerSearchCtrl.value = textCtrl.value;
              });
            }
          },
          onSubmitted: (_) {
            final matches = _searchMatches(textCtrl.text, targets);
            if (matches.isNotEmpty) {
              _goToSearchTarget(matches.first);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No matching pages found.'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildNavSectionHeader(String title) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF565658),
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }

  String get _currentTitle {
    switch (_selectedIndex) {
      case 0:
        return 'Dashboard';
      case 1:
        return 'Work Sheets';
      case 2:
        return 'Files';
      case 3:
        return 'Audit Log';
      case 4:
        return 'Users';
      case 5:
        return 'Edit Requests';
      case 6:
        return 'Settings';
      default:
        return 'Dashboard';
    }
  }

  // ── Header profile (for top bar) ──
  Widget _buildHeaderProfile(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = auth.user;
    final fullName = user?.fullName ?? user?.username ?? 'User';
    final role = user?.role ?? 'User';

    // Get initials
    String initials = 'U';
    if (fullName.isNotEmpty) {
      final parts = fullName.trim().split(' ');
      if (parts.length >= 2) {
        initials = '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      } else {
        initials = parts.first[0].toUpperCase();
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: _kSidebarActiveBlue,
          child: Text(
            initials,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fullName,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color:
                    isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937),
              ),
            ),
            Text(
              role,
              style: TextStyle(
                fontSize: 11,
                color:
                    isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280),
              ),
            ),
          ],
        ),
        const SizedBox(width: 8),
        Icon(Icons.keyboard_arrow_down,
            size: 18,
            color: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280)),
      ],
    );
  }

  // ── Profile widget ──
  Widget _buildProfile(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? const Color(0xFF374151) : _kBorder;
    final titleColor =
        isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937);
    final subtitleColor =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    if (!_sidebarExpanded) {
      // Collapsed: just show avatar centered
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.lightBlue,
          child: Icon(Icons.person, color: _kSidebarActiveBlue, size: 20),
        ),
      );
    }

    // Expanded: avatar + text
    final role = (auth.user?.role ?? 'Administrator').toLowerCase() == 'admin'
        ? 'Super Admin'
        : (auth.user?.role ?? 'Administrator');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: profileBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.20 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.lightBlue,
            child: Icon(Icons.person, color: _kSidebarActiveBlue, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (auth.user?.fullName ?? 'ADMINISTRATOR').toUpperCase(),
                  style: TextStyle(
                    color: titleColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  role,
                  style: TextStyle(
                    color: subtitleColor,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor =
        isDark ? const Color(0xFFD1D5DB) : _kSidebarInactiveGrey;
    final selectedBg = isDark ? const Color(0x332563EB) : _kSidebarBgActive;
    final selectedBorder =
        isDark ? const Color(0x665B8CFF) : Colors.transparent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.hardEdge,
        child: Ink(
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border:
                selected ? Border.all(color: selectedBorder, width: 1) : null,
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            hoverColor:
                isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
            splashColor:
                isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB),
            onTap: () {
              if (item.index >= 0) {
                setState(() {
                  _selectedIndex = item.index;
                  if (item.label == 'Edit Requests') {
                    _pendingEditRequestCount = 0;
                  }
                });
              }
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canShowLabel =
                    _sidebarExpanded && constraints.maxWidth >= 120;
                return Stack(
                  children: [
                    if (selected)
                      Positioned(
                        left: 0,
                        top: 10,
                        bottom: 10,
                        child: Container(
                          width: 3,
                          decoration: BoxDecoration(
                            color: _kSidebarActiveBlue,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: canShowLabel ? 14 : 0,
                        vertical: 13,
                      ),
                      child: Row(
                        mainAxisAlignment: canShowLabel
                            ? MainAxisAlignment.start
                            : MainAxisAlignment.center,
                        children: [
                          Icon(
                            item.icon,
                            color:
                                selected ? _kSidebarActiveBlue : inactiveColor,
                            size: 20,
                          ),
                          if (canShowLabel) ...[
                            const SizedBox(width: 12),
                            Flexible(
                              child: Text(
                                item.label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? _kSidebarActiveBlue
                                      : inactiveColor,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (item.label == 'Edit Requests' &&
                                _pendingEditRequestCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.orange[400],
                                  borderRadius: BorderRadius.circular(12),
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
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Logout button ──
  Widget _buildLogoutButton(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inactiveColor =
        isDark ? const Color(0xFFD1D5DB) : _kSidebarInactiveGrey;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor:
              isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6),
          splashColor:
              isDark ? const Color(0xFF4B5563) : const Color(0xFFE5E7EB),
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                scrollable: true,
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
            padding: EdgeInsets.symmetric(
              horizontal: _sidebarExpanded ? 14 : 0,
              vertical: 12,
            ),
            child: Row(
              mainAxisAlignment: _sidebarExpanded
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: inactiveColor, size: 20),
                if (_sidebarExpanded) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'Logout',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: inactiveColor,
                        fontWeight: FontWeight.w400,
                        fontSize: 13,
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
}

// ── Helper model ──
class _NavItem {
  final IconData icon;
  final String label;
  final int index;
  _NavItem(this.icon, this.label, this.index);
}

class _GlobalSearchTarget {
  final String label;
  final String subtitle;
  final int tabIndex;
  final IconData icon;
  final List<String> keywords;
  final String? dashboardSectionId;

  const _GlobalSearchTarget({
    required this.label,
    required this.subtitle,
    required this.tabIndex,
    required this.icon,
    this.keywords = const [],
    this.dashboardSectionId,
  });
}

// ── Header icon button (notification, chat, etc.) ──
class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final int badge;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background =
        isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);
    final borderColor = isDark ? const Color(0xFF374151) : _kBorder;
    final iconColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 18, color: iconColor),
            if (badge > 0)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  DASHBOARD CONTENT (main area)
// ═══════════════════════════════════════════════════════
enum _TrendGroupBy { day, month, year }

class _DashboardContent extends StatefulWidget {
  final String? jumpToSectionId;
  final int jumpToSectionToken;

  const _DashboardContent({
    this.jumpToSectionId,
    this.jumpToSectionToken = 0,
  });

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  final _searchCtrl = TextEditingController();
  final _productNameFilterCtrl = TextEditingController();
  final _qbCodeFilterCtrl = TextEditingController();
  final ScrollController _mainScrollController = ScrollController();
  final ScrollController _filterRowScrollController = ScrollController();
  final PageController _statPageController = PageController();
  int _alertPage = 0;
  static const int _alertPageSize = 8;
  String _selectedProductStockKey = '__all__';
  int _statPageIndex = 0;
  int? _selectedStatCardIndex;

  _TrendGroupBy _trendGroupBy = _TrendGroupBy.month;

  // Sheet filter state
  Set<int> _selectedSheetIds = {}; // empty = all sheets
  int? _lastAppliedSheetId;
  bool _userOverrodeSheetFilter = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final data = context.read<DataProvider>();
      // Load available sheets for the filter, then load dashboard
      data.loadInventorySheets();
      final currentSheetId = data.currentSheetId;
      if (currentSheetId != null) {
        _selectedSheetIds = {currentSheetId};
        _lastAppliedSheetId = currentSheetId;
        data.loadInventoryDashboard(sheetIds: [currentSheetId]);
      } else {
        data.loadInventoryDashboard();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DashboardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.jumpToSectionToken != oldWidget.jumpToSectionToken &&
        widget.jumpToSectionId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        scrollToSection(widget.jumpToSectionId!);
      });
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _productNameFilterCtrl.dispose();
    _qbCodeFilterCtrl.dispose();
    _mainScrollController.dispose();
    _filterRowScrollController.dispose();
    _statPageController.dispose();
    super.dispose();
  }

  void scrollToSection(String sectionId) {
    _mainScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _applySheetFilter(Set<int> ids, {bool markUser = true}) async {
    setState(() {
      _selectedSheetIds = ids;
      _selectedProductStockKey = '__all__';
      if (markUser) _userOverrodeSheetFilter = true;
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

  String _productNameOf(Map<String, dynamic> item) =>
      (item['product_name'] ?? item['name'] ?? '').toString().toLowerCase();

  String _qbCodeOf(Map<String, dynamic> item) =>
      (item['qb_code'] ?? item['qc_code'] ?? item['code'] ?? '')
          .toString()
          .toLowerCase();

  bool _matchesDashboardFilters(Map<String, dynamic> item) {
    final productQ = _productNameFilterCtrl.text.trim().toLowerCase();
    final qbQ = _qbCodeFilterCtrl.text.trim().toLowerCase();
    final productOk =
        productQ.isEmpty || _productNameOf(item).contains(productQ);
    final qbOk = qbQ.isEmpty || _qbCodeOf(item).contains(qbQ);
    return productOk && qbOk;
  }

  List<int> _trendYears(List<Map<String, dynamic>> dailyTrendRaw) {
    final years = <int>{};
    for (final row in dailyTrendRaw) {
      final date = row['date']?.toString();
      if (date == null || date.length < 4) continue;
      final y = int.tryParse(date.substring(0, 4));
      if (y != null) years.add(y);
    }
    final list = years.toList()..sort();
    return list;
  }

  List<int> _trendMonths(List<Map<String, dynamic>> dailyTrendRaw, int year) {
    final months = <int>{};
    for (final row in dailyTrendRaw) {
      final date = row['date']?.toString();
      if (date == null || date.length < 7) continue;
      if (!date.startsWith('$year-')) continue;
      final m = int.tryParse(date.substring(5, 7));
      if (m != null && m >= 1 && m <= 12) months.add(m);
    }
    final list = months.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> _filterDailyTrend(
    List<Map<String, dynamic>> dailyTrendRaw, {
    required int year,
    int? month,
  }) {
    final ym =
        month == null ? '$year-' : '$year-${month.toString().padLeft(2, '0')}';
    return dailyTrendRaw.where((row) {
      final date = row['date']?.toString();
      if (date == null) return false;
      return month == null ? date.startsWith(ym) : date.startsWith(ym);
    }).toList();
  }

  String _dayLabel(String ymd) {
    // ymd expected: YYYY-MM-DD
    try {
      final dt = DateTime.parse(ymd);
      final mon = (dt.month >= 1 && dt.month <= 12)
          ? _kMonthNamesShort[dt.month - 1]
          : '';
      return '$mon ${dt.day}';
    } catch (_) {
      return ymd;
    }
  }

  int _criticalCount(List<Map<String, dynamic>> lowStockItems) {
    return lowStockItems.where((item) {
      final status = (item['stock_status'] ?? '').toString().toLowerCase();
      final current = (item['current_stock'] as num?)?.toInt() ?? 0;
      final critical = (item['critical_qty'] as num?)?.toInt() ?? 0;
      return status == 'critical' || current <= critical;
    }).length;
  }

  int _monthlyUsage(List<Map<String, dynamic>> trendData) {
    return trendData.fold<int>(
      0,
      (sum, row) => sum + ((row['stock_out'] as num?)?.toInt() ?? 0),
    );
  }

  int _healthScore({
    required int totalProducts,
    required int lowCount,
    required int criticalCount,
  }) {
    if (totalProducts <= 0) return 100;
    final raw = ((totalProducts - (criticalCount * 1.5) - (lowCount * 0.7)) /
            totalProducts) *
        100;
    return raw.clamp(0, 100).round();
  }

  int? _parseMonthFromMonthLabel(String label) {
    // Expected formats include: "Mar 26", "Mar 2026"
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return null;
    final mon = parts.first.toLowerCase();
    const map = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    return map[mon];
  }

  int? _parseYearFromMonthLabel(String label) {
    // Expected formats include: "Mar 26", "Mar 2026"
    final parts = label.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return null;
    final raw = int.tryParse(parts[1]);
    if (raw == null) return null;
    if (raw >= 1000) return raw;
    // Assume 20xx for 2-digit years used by backend
    return 2000 + raw;
  }

  List<int> _monthlyTrendYears(List<Map<String, dynamic>> monthlyTrendRaw) {
    final years = <int>{};
    for (final row in monthlyTrendRaw) {
      final label = row['month_label']?.toString() ?? '';
      final y = _parseYearFromMonthLabel(label);
      if (y != null) years.add(y);
    }
    final list = years.toList()..sort();
    return list;
  }

  List<Map<String, dynamic>> _filterMonthlyTrend(
    List<Map<String, dynamic>> monthlyTrendRaw, {
    required int year,
  }) {
    return monthlyTrendRaw.where((row) {
      final label = row['month_label']?.toString() ?? '';
      return _parseYearFromMonthLabel(label) == year;
    }).toList();
  }

  List<Map<String, dynamic>> _aggregateDailyToMonthly(
    List<Map<String, dynamic>> daily,
    int year,
  ) {
    final map = <int, Map<String, num>>{}; // month -> sums
    for (final row in daily) {
      final date = row['date']?.toString();
      if (date == null) continue;
      if (!date.startsWith('$year-')) continue;
      final m = int.tryParse(date.substring(5, 7));
      if (m == null || m < 1 || m > 12) continue;
      final inQty = (row['stock_in'] as num?) ?? 0;
      final outQty = (row['stock_out'] as num?) ?? 0;
      final cur = map[m] ?? {'stock_in': 0, 'stock_out': 0};
      cur['stock_in'] = (cur['stock_in'] ?? 0) + inQty;
      cur['stock_out'] = (cur['stock_out'] ?? 0) + outQty;
      map[m] = cur;
    }
    final months = map.keys.toList()..sort();
    return months.map((m) {
      final sums = map[m]!;
      return {
        'x_label': _kMonthNamesShort[m - 1],
        'stock_in': (sums['stock_in'] ?? 0),
        'stock_out': (sums['stock_out'] ?? 0),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _aggregateDailyToYearly(
    List<Map<String, dynamic>> daily,
  ) {
    final map = <int, Map<String, num>>{};
    for (final row in daily) {
      final date = row['date']?.toString();
      if (date == null || date.length < 4) continue;
      final y = int.tryParse(date.substring(0, 4));
      if (y == null) continue;
      final inQty = (row['stock_in'] as num?) ?? 0;
      final outQty = (row['stock_out'] as num?) ?? 0;
      final cur = map[y] ?? {'stock_in': 0, 'stock_out': 0};
      cur['stock_in'] = (cur['stock_in'] ?? 0) + inQty;
      cur['stock_out'] = (cur['stock_out'] ?? 0) + outQty;
      map[y] = cur;
    }
    final years = map.keys.toList()..sort();
    return years.map((y) {
      final sums = map[y]!;
      return {
        'x_label': '$y',
        'stock_in': (sums['stock_in'] ?? 0),
        'stock_out': (sums['stock_out'] ?? 0),
      };
    }).toList();
  }

  List<Map<String, dynamic>> _aggregateMonthlyToYearly(
    List<Map<String, dynamic>> monthlyTrendRaw,
  ) {
    final map = <int, Map<String, num>>{};
    for (final row in monthlyTrendRaw) {
      final label = row['month_label']?.toString() ?? '';
      final y = _parseYearFromMonthLabel(label);
      if (y == null) continue;
      final inQty = (row['stock_in'] as num?) ?? 0;
      final outQty = (row['stock_out'] as num?) ?? 0;
      final cur = map[y] ?? {'stock_in': 0, 'stock_out': 0};
      cur['stock_in'] = (cur['stock_in'] ?? 0) + inQty;
      cur['stock_out'] = (cur['stock_out'] ?? 0) + outQty;
      map[y] = cur;
    }
    final years = map.keys.toList()..sort();
    return years.map((y) {
      final sums = map[y]!;
      return {
        'x_label': '$y',
        'stock_in': (sums['stock_in'] ?? 0),
        'stock_out': (sums['stock_out'] ?? 0),
      };
    }).toList();
  }

  Widget _buildTrendGroupByControl() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFDCE3EC);
    final hint = isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final inputBg = isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);

    final effective = _trendGroupBy;

    const options = <_TrendGroupBy>[
      _TrendGroupBy.day,
      _TrendGroupBy.month,
      _TrendGroupBy.year,
    ];

    String label(_TrendGroupBy g) {
      switch (g) {
        case _TrendGroupBy.day:
          return 'Day';
        case _TrendGroupBy.month:
          return 'Month';
        case _TrendGroupBy.year:
          return 'Year';
      }
    }

    return SizedBox(
      width: 128,
      child: DropdownButtonFormField<_TrendGroupBy>(
        value: effective,
        isDense: true,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: inputBg,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: border),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            borderSide: BorderSide(color: AppColors.primaryBlue),
          ),
          prefixIcon: Icon(Icons.tune_rounded, size: 16, color: hint),
        ),
        icon: Icon(Icons.expand_more_rounded, size: 18, color: hint),
        style: TextStyle(
          fontSize: 12,
          color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
          fontWeight: FontWeight.w600,
        ),
        dropdownColor:
            isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _trendGroupBy = v;
          });
        },
        items: options
            .map((g) => DropdownMenuItem(value: g, child: Text(label(g))))
            .toList(),
      ),
    );
  }

  Widget _buildDashboardFilters({bool decorate = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0F172A) : Colors.white;
    final border = isDark ? const Color(0xFF334155) : const Color(0xFFDCE3EC);
    final hint = isDark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);
    final inputBg = isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);

    Widget inputField({
      required String hintText,
      required IconData icon,
      required TextEditingController ctrl,
    }) {
      return SizedBox(
        width: 230,
        child: TextField(
          controller: ctrl,
          onChanged: (_) => setState(() => _alertPage = 0),
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
          ),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 12, color: hint),
            prefixIcon: Icon(icon, size: 16, color: hint),
            filled: true,
            fillColor: inputBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primaryBlue),
            ),
          ),
        ),
      );
    }

    final content = Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        inputField(
          hintText: 'Filter Product Name',
          icon: Icons.inventory_2_outlined,
          ctrl: _productNameFilterCtrl,
        ),
        inputField(
          hintText: 'Filter QB Code',
          icon: Icons.tag_outlined,
          ctrl: _qbCodeFilterCtrl,
        ),
        TextButton.icon(
          onPressed: () {
            _productNameFilterCtrl.clear();
            _qbCodeFilterCtrl.clear();
            setState(() => _alertPage = 0);
          },
          style: TextButton.styleFrom(
            foregroundColor:
                isDark ? const Color(0xFFE2E8F0) : AppColors.primaryBlue,
            backgroundColor: inputBg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: border),
            ),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Reset Filters'),
        ),
      ],
    );

    if (!decorate) return content;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: content,
    );
  }

  Widget _buildSheetFilter(
      {required List<Map<String, dynamic>> sheets, bool decorate = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111827) : Colors.white;
    final border = isDark ? const Color(0xFF334155) : _kBorder.withOpacity(0.6);
    final text = isDark ? const Color(0xFFD1D5DB) : const Color(0xFF5F6368);
    final clearBg = isDark ? const Color(0xFF0F172A) : Colors.grey.shade100;
    final clearBorder = isDark ? const Color(0xFF334155) : Colors.grey.shade300;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.filter_list_rounded, size: 18, color: text),
        const SizedBox(width: 8),
        Text(
          'Filter by Sheet:',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: text,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(width: 12),
        _SheetDropdown(
          sheets: sheets,
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
                color: clearBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: clearBorder),
              ),
              child: Text(
                'Clear',
                style: TextStyle(
                  fontSize: 11,
                  color: text,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ],
    );

    if (!decorate) return content;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.04),
            blurRadius: 4,
            offset: const Offset(0, 1),
          )
        ],
      ),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DataProvider>(
      builder: (context, data, _) {
        final sheets = data.inventorySheets;
        final currentSheetId = data.currentSheetId;
        if (!_userOverrodeSheetFilter &&
            currentSheetId != null &&
            _lastAppliedSheetId != currentSheetId) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            setState(() {
              _selectedSheetIds = {currentSheetId};
              _selectedProductStockKey = '__all__';
              _lastAppliedSheetId = currentSheetId;
            });
            data.loadInventoryDashboard(sheetIds: [currentSheetId]);
          });
        }
        final inv = data.inventoryDashboardData;

        if (data.isLoading && inv == null) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  'Loading dashboard…',
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF9CA3AF)
                        : const Color(0xFF5F6368),
                  ),
                ),
              ],
            ),
          );
        }

        final productStocksRaw = inv?.productStocks ?? const [];
        final monthlyTrendRaw = inv?.monthlyTrend ?? const [];
        final dailyTrendRaw = inv?.dailyTrend ?? const [];
        final allAlerts = inv?.lowStockItems ?? const [];

        final filteredProductStocks = productStocksRaw
            .where((item) => _matchesDashboardFilters(item))
            .toList();
        final filteredAlertsBase =
            allAlerts.where((item) => _matchesDashboardFilters(item)).toList();
        final supportsDay = dailyTrendRaw.isNotEmpty;
        final effectiveGroupBy = _trendGroupBy;

        final yearsFromData = supportsDay
            ? _trendYears(List<Map<String, dynamic>>.from(dailyTrendRaw))
            : _monthlyTrendYears(
                List<Map<String, dynamic>>.from(monthlyTrendRaw));
        final availableYears = yearsFromData.isNotEmpty
            ? yearsFromData
            : <int>[DateTime.now().year];

        final effectiveTrendYear = availableYears.isNotEmpty
            ? availableYears.last
            : DateTime.now().year;

        final availableMonths = supportsDay
            ? _trendMonths(
                List<Map<String, dynamic>>.from(dailyTrendRaw),
                effectiveTrendYear,
              )
            : const <int>[];

        final effectiveTrendMonth = (effectiveGroupBy == _TrendGroupBy.day)
            ? (availableMonths.isNotEmpty ? availableMonths.last : null)
            : null;

        List<Map<String, dynamic>> trendData;
        if (effectiveGroupBy == _TrendGroupBy.day) {
          final filteredDaily = supportsDay
              ? _filterDailyTrend(
                  List<Map<String, dynamic>>.from(dailyTrendRaw),
                  year: effectiveTrendYear,
                  month: effectiveTrendMonth,
                )
              : const <Map<String, dynamic>>[];
          trendData = filteredDaily.map((row) {
            final date = row['date']?.toString() ?? '';
            return {
              ...row,
              'x_label': date.isNotEmpty ? _dayLabel(date) : '-',
            };
          }).toList();
        } else if (effectiveGroupBy == _TrendGroupBy.month) {
          if (supportsDay) {
            trendData = _aggregateDailyToMonthly(
              List<Map<String, dynamic>>.from(dailyTrendRaw),
              effectiveTrendYear,
            );
          } else {
            final filteredMonthly = _filterMonthlyTrend(
              List<Map<String, dynamic>>.from(monthlyTrendRaw),
              year: effectiveTrendYear,
            );
            trendData = filteredMonthly.map((row) {
              final label = row['month_label']?.toString() ?? '-';
              final m = _parseMonthFromMonthLabel(label);
              final x = (m != null && m >= 1 && m <= 12)
                  ? _kMonthNamesShort[m - 1]
                  : label;
              return {
                ...row,
                'x_label': x,
              };
            }).toList();
          }
        } else {
          // Year
          if (supportsDay) {
            trendData = _aggregateDailyToYearly(
              List<Map<String, dynamic>>.from(dailyTrendRaw),
            );
          } else {
            trendData = _aggregateMonthlyToYearly(
              List<Map<String, dynamic>>.from(monthlyTrendRaw),
            );
          }
        }

        final query = _searchCtrl.text.trim().toLowerCase();
        final filtered = query.isEmpty
            ? filteredAlertsBase
            : filteredAlertsBase.where((i) {
                final product = _productNameOf(i);
                final code = _qbCodeOf(i);
                return product.contains(query) || code.contains(query);
              }).toList();

        final totalProducts = filteredProductStocks.isNotEmpty
            ? filteredProductStocks.length
            : productStocksRaw.length;
        final lowCount = filteredAlertsBase.length;
        final criticalCount = _criticalCount(filteredAlertsBase);
        final healthScore = _healthScore(
          totalProducts: totalProducts,
          lowCount: lowCount,
          criticalCount: criticalCount,
        );

        final pageCount =
            ((filtered.length) / _alertPageSize).ceil().clamp(1, 999);
        final safeAlertPage = _alertPage.clamp(0, pageCount - 1);
        final pagedAlerts = filtered
            .skip(safeAlertPage * _alertPageSize)
            .take(_alertPageSize)
            .toList();

        return RefreshIndicator(
          onRefresh: () async {
            await Future.wait([
              data.loadInventorySheets(),
              data.loadInventoryDashboard(
                sheetIds: _selectedSheetIds.isEmpty
                    ? null
                    : _selectedSheetIds.toList(),
              ),
            ]);
          },
          child: SingleChildScrollView(
            controller: _mainScrollController,
            primary: false,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Combined filter row ─────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF0F172A)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF334155)
                          : const Color(0xFFDCE3EC),
                    ),
                  ),
                  child: SingleChildScrollView(
                    controller: _filterRowScrollController,
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (sheets.isNotEmpty) ...[
                          _buildSheetFilter(sheets: sheets, decorate: false),
                          const SizedBox(width: 20),
                        ],
                        _buildDashboardFilters(
                          decorate: false,
                        ),
                        const SizedBox(width: 16),
                        _StockAlertWidget(
                          criticalItems: criticalCount,
                          lowStockItems: lowCount,
                          decorate: false,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // ── Section: Summary Cards ────────────────────────────────
                _SectionTitle(title: 'Inventory Summary'),
                const SizedBox(height: 14),
                _buildStatCards(
                  inv: inv,
                  totalProducts: totalProducts,
                  lowCount: lowCount,
                  criticalCount: criticalCount,
                  healthScore: healthScore,
                  trendData: trendData,
                ),
                const SizedBox(height: 28),

                // ── Section: Stock Analytics ────────────────────────────
                _SectionTitle(title: 'Stock Analytics'),
                const SizedBox(height: 14),

                // Middle Section – Stock Level Status + Stock In vs Out side by side
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _DashCard(
                          title: 'Stock Level Status',
                          icon: Icons.pie_chart_outline_rounded,
                          iconColor: const Color(0xFF2563EB),
                          child: SizedBox(
                            height: 240,
                            child: _StockStatusDonutChart(
                              key: const ValueKey('chart_stock_status'),
                              totalProducts: totalProducts,
                              lowStockCount: lowCount,
                              criticalCount: criticalCount,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DashCard(
                          title: 'Stock In vs Stock Out',
                          icon: Icons.compare_arrows_rounded,
                          iconColor: const Color(0xFF2E7D32),
                          child: SizedBox(
                            height: 240,
                            child: _StockInOutChart(
                              key: const ValueKey('chart_stock_inout'),
                              data: trendData,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Trend Section
                _DashCard(
                  title: 'Inventory Movement Trend',
                  icon: Icons.trending_up_rounded,
                  iconColor: AppColors.primaryBlue,
                  headerTrailing: _buildTrendGroupByControl(),
                  child: SizedBox(
                    height: 300,
                    child: _MonthlyUsageChart(
                      key: const ValueKey('chart_monthly_usage'),
                      data: trendData,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Bottom analytics section - side by side
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _DashCard(
                          title: 'Top Used Products',
                          icon: Icons.bar_chart_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          child: SizedBox(
                            height: 260,
                            child: _TopUsedProductsChart(
                                key: const ValueKey('chart_top_used'),
                                data: filteredProductStocks),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _DashCard(
                          title: 'Stock vs Maintaining Level',
                          icon: Icons.balance_outlined,
                          iconColor: const Color(0xFF0EA5E9),
                          child: SizedBox(
                            height: 260,
                            child: _StockVsMaintainingChart(
                                key: const ValueKey('chart_stock_maintaining'),
                                data: filteredProductStocks),
                          ),
                        ),
                      ),
                    ],
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
                              count: criticalCount,
                              color: Colors.red[700]!,
                            ),
                            const SizedBox(width: 10),
                            _AlertBadge(
                              label: 'Low Stock',
                              count: lowCount,
                              color: Colors.orange[700]!,
                            ),
                            const Spacer(),
                            // Search
                            SizedBox(
                              width: 280,
                              child: TextField(
                                controller: _searchCtrl,
                                decoration: InputDecoration(
                                  hintText: 'Search material or QB code…',
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
                      Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? const Color(0xFF1F2937)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${filtered.length} item(s)  •  Page ${safeAlertPage + 1} of $pageCount',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF5F6368),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(Icons.chevron_left,
                                  size: 20,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF5F6368)),
                              visualDensity: VisualDensity.compact,
                              onPressed: safeAlertPage > 0
                                  ? () => setState(
                                      () => _alertPage = safeAlertPage - 1)
                                  : null,
                            ),
                            IconButton(
                              icon: Icon(Icons.chevron_right,
                                  size: 20,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : const Color(0xFF5F6368)),
                              visualDensity: VisualDensity.compact,
                              onPressed: safeAlertPage < pageCount - 1
                                  ? () => setState(
                                      () => _alertPage = safeAlertPage + 1)
                                  : null,
                            ),
                          ],
                        ),
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
  Widget _buildStatCards({
    required InventoryDashboardData? inv,
    required int totalProducts,
    required int lowCount,
    required int criticalCount,
    required int healthScore,
    required List<Map<String, dynamic>> trendData,
  }) {
    final totalStockQty = _selectedStockQty(inv);
    final monthlyUsage = _monthlyUsage(trendData);
    final cards = [
      _StatCardData(
        title: 'Total Products',
        value: '$totalProducts',
        icon: Icons.inventory_2_outlined,
        color: const Color(0xFF0EA5E9),
        bgColor: const Color(0xFFE0F2FE),
        trendPct: 8.3,
        trendUp: true,
        sparkline: const [2, 3, 4, 5, 6, 7, 8],
      ),
      _StatCardData(
        title: 'Total Quantity',
        value: _fmt(totalStockQty),
        icon: Icons.stacked_bar_chart_rounded,
        color: const Color(0xFF2563EB),
        bgColor: const Color(0xFFDBEAFE),
        trendPct: 11.2,
        trendUp: true,
        sparkline: const [3, 4, 4, 5, 6, 6, 7],
        compactControl: inv != null && inv.productStocks.isNotEmpty
            ? _StockQtyFilterDropdown(
                selectedKey: _selectedProductStockKey,
                productStocks: inv.productStocks,
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedProductStockKey = value);
                },
              )
            : null,
      ),
      _StatCardData(
        title: 'Low Stock Items',
        value: '$lowCount',
        icon: Icons.warning_amber_rounded,
        color: const Color(0xFFD97706),
        bgColor: const Color(0xFFFEF3C7),
        highlight: lowCount > 0,
        trendPct: 4.4,
        trendUp: false,
        sparkline: const [3, 4, 3, 4, 4, 5, 6],
      ),
      _StatCardData(
        title: 'Critical Stock Items',
        value: '$criticalCount',
        icon: Icons.error_outline_rounded,
        color: const Color(0xFFC62828),
        bgColor: AppColors.lightRed,
        highlight: criticalCount > 0,
        trendPct: 17.8,
        trendUp: false,
        sparkline: const [6, 5, 4, 4, 3, 3, 2],
      ),
      _StatCardData(
        title: 'Inventory Health Score',
        value: '$healthScore%',
        icon: Icons.health_and_safety_outlined,
        color: const Color(0xFF2E7D32),
        bgColor: const Color(0xFFE8F5E9),
        trendPct: (healthScore / 10).clamp(0, 10).toDouble(),
        trendUp: true,
        sparkline: const [2, 2, 3, 4, 4, 6, 7],
      ),
      _StatCardData(
        title: 'Monthly Usage',
        value: _fmt(monthlyUsage),
        icon: Icons.output_rounded,
        color: const Color(0xFF7C3AED),
        bgColor: const Color(0xFFEDE9FE),
        trendPct: 6.2,
        trendUp: false,
        sparkline: const [6, 5, 5, 4, 4, 3, 3],
      ),
    ];

    return LayoutBuilder(builder: (context, constraints) {
      const arrowW = 40.0;
      const gap = 16.0;
      final pageCount = (cards.length / 3).ceil();
      final availableW = constraints.maxWidth - arrowW - gap;
      final cardW = (availableW - 2 * gap) / 3;

      return Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 232,
              child: PageView.builder(
                controller: _statPageController,
                itemCount: pageCount,
                onPageChanged: (index) =>
                    setState(() => _statPageIndex = index),
                itemBuilder: (context, pageIndex) {
                  final start = pageIndex * 3;
                  final slice = cards.skip(start).take(3).toList();
                  return Row(
                    children: slice.asMap().entries.map((e) {
                      final cardIndex = start + e.key;
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (e.key > 0) const SizedBox(width: gap),
                          _StatCard(
                            data: e.value,
                            width: cardW,
                            isSelected: _selectedStatCardIndex == cardIndex,
                            onTap: () {
                              setState(() {
                                _selectedStatCardIndex =
                                    _selectedStatCardIndex == cardIndex
                                        ? null
                                        : cardIndex;
                              });
                            },
                          ),
                        ],
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _StatArrowButton(
                icon: Icons.chevron_left,
                enabled: _statPageIndex > 0,
                onTap: () {
                  if (_statPageIndex > 0) {
                    _statPageController.previousPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
              const SizedBox(height: 8),
              _StatArrowButton(
                icon: Icons.chevron_right,
                enabled: _statPageIndex < pageCount - 1,
                onTap: () {
                  if (_statPageIndex < pageCount - 1) {
                    _statPageController.nextPage(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                    );
                  }
                },
              ),
            ],
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: isDark ? const Color(0xFFE5E7EB) : const Color(0xFF1F2937),
        letterSpacing: 0.1,
      ),
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
  final double? trendPct;
  final bool trendUp;
  final List<double> sparkline;

  const _StatCardData({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.bgColor,
    this.highlight = false,
    this.compactControl,
    this.trendPct,
    this.trendUp = true,
    this.sparkline = const [2, 3, 4, 3, 5, 6, 8],
  });
}

// ── Stat card widget ───────────────────────────────────────────────────────────
class _StatCard extends StatefulWidget {
  final _StatCardData data;
  final double width;
  final bool isSelected;
  final VoidCallback onTap;

  const _StatCard({
    required this.data,
    required this.width,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_StatCard> createState() => _StatCardState();
}

class _StatCardState extends State<_StatCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardTop = isDark ? const Color(0xFF0F172A) : Colors.white;
    final cardBottom =
        isDark ? const Color(0xFF0B1220) : d.bgColor.withValues(alpha: 0.25);
    final border = isDark ? const Color(0xFF334155) : _kBorder.withOpacity(0.6);
    final titleColor =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final valueColor =
        isDark ? const Color(0xFFF3F4F6) : const Color(0xFF111827);
    final subMuted = isDark ? const Color(0xFF94A3B8) : const Color(0xFF9CA3AF);

    // Theme-aware icon styling: the provided bgColor values are light-mode
    // tints, so in dark mode we derive a darker tint from the accent color.
    final iconBg = isDark
        ? Color.alphaBlend(d.color.withValues(alpha: 0.18), cardTop)
        : d.bgColor;
    final iconFg = isDark ? d.color.withValues(alpha: 0.95) : d.color;
    const cardHeight = 220.0;
    final showCompactControl = d.compactControl != null;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          height: cardHeight,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                cardTop,
                cardBottom,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border, width: 0.8),
            boxShadow: [
              BoxShadow(
                color: _hovered || widget.isSelected
                    ? d.color.withValues(alpha: 0.18)
                    : Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                blurRadius: _hovered || widget.isSelected ? 20 : 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: iconBg,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(d.icon, color: iconFg, size: 24),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        d.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        d.value,
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: valueColor,
                          letterSpacing: -0.3,
                          height: 1.0,
                        ),
                      ),
                      if (d.trendPct != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              d.trendUp
                                  ? Icons.arrow_drop_up
                                  : Icons.arrow_drop_down,
                              size: 20,
                              color:
                                  d.trendUp ? const Color(0xFF16A34A) : d.color,
                            ),
                            Text(
                              '${d.trendPct!.toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: d.trendUp
                                    ? const Color(0xFF16A34A)
                                    : d.color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'last month',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: subMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (showCompactControl) ...[
                        const SizedBox(height: 12),
                        d.compactControl!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Align(
                  alignment: Alignment.topRight,
                  child: _MiniSparkline(
                    bars: d.sparkline,
                    color: d.trendUp ? const Color(0xFF22C55E) : d.color,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatArrowButton extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _StatArrowButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = enabled
        ? (isDark ? const Color(0xFF111827) : Colors.white)
        : (isDark ? const Color(0xFF1F2937) : const Color(0xFFF3F4F6));
    final border = isDark ? const Color(0xFF334155) : _kBorder;
    final iconColor = enabled
        ? (isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280))
        : (isDark ? const Color(0xFF6B7280) : const Color(0xFFBDBDBD));
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: border),
          boxShadow: enabled
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Icon(
          icon,
          size: 20,
          color: iconColor,
        ),
      ),
    );
  }
}

class _MiniSparkline extends StatelessWidget {
  final List<double> bars;
  final Color color;

  const _MiniSparkline({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxVal = bars.isEmpty
        ? 1.0
        : bars.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);

    return SizedBox(
      width: 62,
      height: 40,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: bars
            .map(
              (v) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Container(
                    height: 8 + (v / maxVal) * 24,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

// ── Total Stock Qty filter dropdown ───────────────────────────────────────────
class _StockQtyFilterDropdown extends StatefulWidget {
  final String selectedKey;
  final List<Map<String, dynamic>> productStocks;
  final ValueChanged<String?> onChanged;

  const _StockQtyFilterDropdown({
    required this.selectedKey,
    required this.productStocks,
    required this.onChanged,
  });

  @override
  State<_StockQtyFilterDropdown> createState() =>
      _StockQtyFilterDropdownState();
}

class _StockQtyFilterDropdownState extends State<_StockQtyFilterDropdown> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = _hovered
        ? (isDark ? const Color(0xFF1E293B) : const Color(0xFFE3F2FD))
        : (isDark ? const Color(0xFF111827) : const Color(0xFFF5F7FA));
    final border = _hovered
        ? const Color(0xFF0277BD)
        : (isDark ? const Color(0xFF334155) : const Color(0xFFCFD8DC));
    final iconColor = _hovered
        ? const Color(0xFF0277BD)
        : (isDark ? const Color(0xFF94A3B8) : const Color(0xFF78909C));
    final textColor = _hovered
        ? const Color(0xFF0277BD)
        : (isDark ? const Color(0xFFD1D5DB) : const Color(0xFF37474F));
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(top: 4),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: bg,
          border: Border.all(color: border, width: 1),
          borderRadius: BorderRadius.circular(20),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: const Color(0xFF0277BD).withValues(alpha: 0.10),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  )
                ]
              : [],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.filter_list_rounded,
              size: 11,
              color: iconColor,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: widget.selectedKey,
                  isDense: true,
                  isExpanded: true,
                  borderRadius: BorderRadius.circular(10),
                  icon: Icon(
                    Icons.expand_more_rounded,
                    size: 13,
                    color: iconColor,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  onChanged: widget.onChanged,
                  items: [
                    const DropdownMenuItem<String>(
                      value: '__all__',
                      child: Text('All Products'),
                    ),
                    ...widget.productStocks.map((p) {
                      final name = p['product_name']?.toString() ?? '-';
                      final code = p['qb_code']?.toString() ??
                          p['qc_code']?.toString() ??
                          '';
                      // Must match _productStockKey format: '$name|$code' lowercase
                      final key =
                          '${name.trim().toLowerCase()}|${code.trim().toLowerCase()}';
                      return DropdownMenuItem<String>(
                        value: key,
                        child: Text(
                          code.isEmpty ? name : '$name ($code)',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardTop = isDark ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
    final cardBottom =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFF);
    final border =
        isDark ? const Color(0xFF334155) : _kBorder.withOpacity(0.55);
    final titleColor =
        isDark ? const Color(0xFFE5E7EB) : const Color(0xFF202124);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cardTop, cardBottom],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border, width: 0.9),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
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
                          (iconColor ?? _kHeaderOrange).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(icon,
                        size: 16, color: iconColor ?? _kHeaderOrange),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: titleColor,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                if (headerTrailing != null) ...[
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: headerTrailing!,
                      ),
                    ),
                  ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 40,
            color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
          ),
          const SizedBox(height: 8),
          Text(message,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500,
              )),
        ],
      ),
    );
  }
}

class _StockAlertWidget extends StatelessWidget {
  final int criticalItems;
  final int lowStockItems;
  final bool decorate;

  const _StockAlertWidget({
    required this.criticalItems,
    required this.lowStockItems,
    this.decorate = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final containerBg = isDark ? const Color(0xFF111827) : Colors.white;
    final containerBorder =
        isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final criticalBg =
        isDark ? const Color(0xFF3A1618) : const Color(0xFFFEF2F2);
    final criticalBorder =
        isDark ? const Color(0xFF7F1D1D) : const Color(0xFFFECACA);
    final criticalText =
        isDark ? const Color(0xFFFCA5A5) : const Color(0xFFB91C1C);

    final lowBg = isDark ? const Color(0xFF3F2A10) : const Color(0xFFFFFBEB);
    final lowBorder =
        isDark ? const Color(0xFF92400E) : const Color(0xFFFDE68A);
    final lowText = isDark ? const Color(0xFFFCD34D) : const Color(0xFF92400E);

    Widget statusPill({
      required IconData icon,
      required String label,
      required int value,
      required Color bg,
      required Color border,
      required Color text,
      required Color iconColor,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 6),
            Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: text,
              ),
            ),
          ],
        ),
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        statusPill(
          icon: Icons.error_outline_rounded,
          label: 'Critical',
          value: criticalItems,
          bg: criticalBg,
          border: criticalBorder,
          text: criticalText,
          iconColor: const Color(0xFFEF4444),
        ),
        const SizedBox(width: 8),
        statusPill(
          icon: Icons.warning_amber_rounded,
          label: 'Low Stock',
          value: lowStockItems,
          bg: lowBg,
          border: lowBorder,
          text: lowText,
          iconColor: const Color(0xFFF59E0B),
        ),
      ],
    );

    if (!decorate) return content;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: containerBorder),
      ),
      child: SingleChildScrollView(
        primary: false,
        scrollDirection: Axis.horizontal,
        child: content,
      ),
    );
  }
}

class _StockStatusDonutChart extends StatefulWidget {
  final int totalProducts;
  final int lowStockCount;
  final int criticalCount;

  const _StockStatusDonutChart({
    super.key,
    required this.totalProducts,
    required this.lowStockCount,
    required this.criticalCount,
  });

  @override
  State<_StockStatusDonutChart> createState() => _StockStatusDonutChartState();
}

class _StockStatusDonutChartState extends State<_StockStatusDonutChart> {
  late final TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(enable: true);
  }

  @override
  Widget build(BuildContext context) {
    final normal = (widget.totalProducts - widget.lowStockCount)
        .clamp(0, widget.totalProducts);
    final chartData = [
      {
        'label': 'Normal',
        'value': normal.toDouble(),
        'color': const Color(0xFF22C55E)
      },
      {
        'label': 'Low',
        'value': widget.lowStockCount.toDouble(),
        'color': const Color(0xFFF59E0B)
      },
      {
        'label': 'Critical',
        'value': widget.criticalCount.toDouble(),
        'color': const Color(0xFFEF4444)
      },
    ];

    return SfCircularChart(
      margin: EdgeInsets.zero,
      legend: Legend(
        isVisible: true,
        position: LegendPosition.right,
        overflowMode: LegendItemOverflowMode.wrap,
      ),
      tooltipBehavior: _tooltipBehavior,
      series: <DoughnutSeries<Map<String, dynamic>, String>>[
        DoughnutSeries<Map<String, dynamic>, String>(
          dataSource: chartData,
          animationDuration: 0,
          xValueMapper: (d, _) => d['label'] as String,
          yValueMapper: (d, _) => d['value'] as double,
          pointColorMapper: (d, _) => d['color'] as Color,
          innerRadius: '62%',
          dataLabelSettings: const DataLabelSettings(
            isVisible: true,
            labelPosition: ChartDataLabelPosition.outside,
          ),
        ),
      ],
    );
  }
}

// ── Inventory Movement Trend – Dual Line Chart ───────────────────────────────
class _MonthlyUsageChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  const _MonthlyUsageChart({super.key, required this.data});

  @override
  State<_MonthlyUsageChart> createState() => _MonthlyUsageChartState();
}

class _MonthlyUsageChartState extends State<_MonthlyUsageChart> {
  late final TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(enable: true);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return const _EmptyChart(message: 'No trend data yet');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final axis = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    final grid = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    return SfCartesianChart(
      margin: EdgeInsets.zero,
      plotAreaBorderWidth: 0,
      legend: const Legend(isVisible: true, position: LegendPosition.top),
      tooltipBehavior: _tooltipBehavior,
      primaryXAxis: CategoryAxis(
        labelStyle: TextStyle(fontSize: 10, color: axis),
        majorGridLines: const MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        labelStyle: TextStyle(fontSize: 10, color: axis),
        majorGridLines: MajorGridLines(color: grid, width: 1),
      ),
      series: <CartesianSeries<Map<String, dynamic>, String>>[
        LineSeries<Map<String, dynamic>, String>(
          name: 'Stock In',
          animationDuration: 0,
          color: const Color(0xFF16A34A),
          width: 2.8,
          markerSettings:
              const MarkerSettings(isVisible: true, width: 6, height: 6),
          dataSource: data,
          xValueMapper: (d, _) =>
              d['x_label']?.toString() ??
              d['month_label']?.toString() ??
              d['date']?.toString() ??
              '-',
          yValueMapper: (d, _) => ((d['stock_in'] as num?)?.toDouble() ?? 0),
        ),
        LineSeries<Map<String, dynamic>, String>(
          name: 'Stock Out',
          animationDuration: 0,
          color: const Color(0xFF2563EB),
          width: 2.8,
          markerSettings:
              const MarkerSettings(isVisible: true, width: 6, height: 6),
          dataSource: data,
          xValueMapper: (d, _) =>
              d['x_label']?.toString() ??
              d['month_label']?.toString() ??
              d['date']?.toString() ??
              '-',
          yValueMapper: (d, _) => ((d['stock_out'] as num?)?.toDouble() ?? 0),
        ),
      ],
    );
  }
}

class _TopUsedProductsChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  const _TopUsedProductsChart({super.key, required this.data});

  @override
  State<_TopUsedProductsChart> createState() => _TopUsedProductsChartState();
}

class _TopUsedProductsChartState extends State<_TopUsedProductsChart> {
  late final TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(enable: true);
  }

  double _usage(Map<String, dynamic> item) {
    const keys = [
      'used_qty',
      'total_used',
      'stock_out',
      'used_this_month',
      'out_qty'
    ];
    for (final key in keys) {
      final value = item[key];
      if (value is num) return value.toDouble();
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final sorted = List<Map<String, dynamic>>.from(data)
      ..sort((a, b) => _usage(b).compareTo(_usage(a)));
    final top = sorted.take(8).toList();
    if (top.isEmpty || _usage(top.first) <= 0) {
      return const _EmptyChart(message: 'No usage data available');
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final axis = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    final grid = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

    final chartData = top.map((item) {
      final name = (item['product_name'] ?? item['name'] ?? '-').toString();
      final safeName = name.length > 22 ? '${name.substring(0, 22)}...' : name;
      return {
        'name': safeName,
        'used': _usage(item),
      };
    }).toList();

    return SfCartesianChart(
      margin: EdgeInsets.zero,
      plotAreaBorderWidth: 0,
      tooltipBehavior: _tooltipBehavior,
      primaryXAxis: CategoryAxis(
        labelStyle: TextStyle(color: axis, fontSize: 10),
        majorGridLines: const MajorGridLines(width: 0),
        labelIntersectAction: AxisLabelIntersectAction.rotate45,
      ),
      primaryYAxis: NumericAxis(
        labelStyle: TextStyle(color: axis, fontSize: 10),
        majorGridLines: MajorGridLines(color: grid, width: 1),
      ),
      series: <CartesianSeries<Map<String, dynamic>, String>>[
        BarSeries<Map<String, dynamic>, String>(
          dataSource: chartData,
          animationDuration: 0,
          xValueMapper: (d, _) => d['name'] as String,
          yValueMapper: (d, _) => d['used'] as double,
          color: const Color(0xFFF59E0B),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          dataLabelSettings: const DataLabelSettings(isVisible: true),
        ),
      ],
    );
  }
}

class _StockVsMaintainingChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  const _StockVsMaintainingChart({super.key, required this.data});

  @override
  State<_StockVsMaintainingChart> createState() =>
      _StockVsMaintainingChartState();
}

class _StockVsMaintainingChartState extends State<_StockVsMaintainingChart> {
  late final TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(enable: true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grid = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final axis = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);
    final data = widget.data;
    if (data.isEmpty) {
      return const _EmptyChart(message: 'No stock data yet');
    }

    final items = List<Map<String, dynamic>>.from(data)
      ..sort((a, b) => ((a['current_stock'] as num?)?.toDouble() ?? 0)
          .compareTo((b['current_stock'] as num?)?.toDouble() ?? 0));
    final view = items.take(10).toList();

    return SfCartesianChart(
      margin: EdgeInsets.zero,
      plotAreaBorderWidth: 0,
      legend: const Legend(isVisible: true, position: LegendPosition.top),
      tooltipBehavior: _tooltipBehavior,
      primaryXAxis: CategoryAxis(
        labelStyle: TextStyle(fontSize: 10, color: axis),
        majorGridLines: const MajorGridLines(width: 0),
        labelIntersectAction: AxisLabelIntersectAction.rotate45,
      ),
      primaryYAxis: NumericAxis(
        labelStyle: TextStyle(fontSize: 10, color: axis),
        majorGridLines: MajorGridLines(color: grid, width: 1),
      ),
      series: <CartesianSeries<Map<String, dynamic>, String>>[
        ColumnSeries<Map<String, dynamic>, String>(
          name: 'Current Stock',
          animationDuration: 0,
          color: const Color(0xFF0EA5E9),
          dataSource: view,
          xValueMapper: (d, _) =>
              (d['qb_code'] ?? d['qc_code'] ?? '-').toString(),
          yValueMapper: (d, _) =>
              ((d['current_stock'] as num?)?.toDouble() ?? 0),
        ),
        ColumnSeries<Map<String, dynamic>, String>(
          name: 'Maintaining',
          animationDuration: 0,
          color: const Color(0xFFF59E0B),
          dataSource: view,
          xValueMapper: (d, _) =>
              (d['qb_code'] ?? d['qc_code'] ?? '-').toString(),
          yValueMapper: (d, _) =>
              ((d['maintaining_qty'] as num?)?.toDouble() ?? 0),
        ),
      ],
    );
  }
}

// ── Stock In vs Out – Grouped Bar Chart ───────────────────────────────────────
class _StockInOutChart extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  const _StockInOutChart({super.key, required this.data});

  @override
  State<_StockInOutChart> createState() => _StockInOutChartState();
}

class _StockInOutChartState extends State<_StockInOutChart> {
  late final TooltipBehavior _tooltipBehavior;

  @override
  void initState() {
    super.initState();
    _tooltipBehavior = TooltipBehavior(enable: true);
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) return const _EmptyChart(message: 'No trend data yet');
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grid = isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
    final axis = isDark ? const Color(0xFF9CA3AF) : const Color(0xFF64748B);

    return SfCartesianChart(
      margin: EdgeInsets.zero,
      plotAreaBorderWidth: 0,
      legend: const Legend(isVisible: true, position: LegendPosition.top),
      tooltipBehavior: _tooltipBehavior,
      primaryXAxis: CategoryAxis(
        labelStyle: TextStyle(fontSize: 10, color: axis),
        majorGridLines: const MajorGridLines(width: 0),
      ),
      primaryYAxis: NumericAxis(
        labelStyle: TextStyle(fontSize: 10, color: axis),
        majorGridLines: MajorGridLines(color: grid, width: 1),
      ),
      series: <CartesianSeries<Map<String, dynamic>, String>>[
        ColumnSeries<Map<String, dynamic>, String>(
          name: 'Stock In',
          animationDuration: 0,
          color: const Color(0xFF16A34A),
          dataSource: data,
          xValueMapper: (d, _) =>
              d['x_label']?.toString() ??
              d['month_label']?.toString() ??
              d['date']?.toString() ??
              '-',
          yValueMapper: (d, _) => ((d['stock_in'] as num?)?.toDouble() ?? 0),
        ),
        ColumnSeries<Map<String, dynamic>, String>(
          name: 'Stock Out',
          animationDuration: 0,
          color: const Color(0xFFEF4444),
          dataSource: data,
          xValueMapper: (d, _) =>
              d['x_label']?.toString() ??
              d['month_label']?.toString() ??
              d['date']?.toString() ??
              '-',
          yValueMapper: (d, _) => ((d['stock_out'] as num?)?.toDouble() ?? 0),
        ),
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
  void didUpdateWidget(covariant _SheetDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isOpen && _overlay != null && oldWidget.sheets != widget.sheets) {
      _overlay?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _closeDropdown(updateState: false);
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

  void _closeDropdown({bool updateState = true}) {
    _overlay?.remove();
    _overlay = null;
    if (updateState && mounted) {
      setState(() => _isOpen = false);
    } else {
      _isOpen = false;
    }
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111827) : Colors.white;
    final border = _isOpen
        ? AppColors.primaryBlue
        : (isDark ? const Color(0xFF334155) : Colors.grey.shade300);
    final textColor = _isOpen
        ? AppColors.primaryBlue
        : (isDark ? const Color(0xFFE5E7EB) : const Color(0xFF202124));
    final iconColor = _isOpen
        ? AppColors.primaryBlue
        : (isDark ? const Color(0xFF9CA3AF) : const Color(0xFF5F6368));
    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleDropdown,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: _isOpen ? 1.5 : 1),
            borderRadius: BorderRadius.circular(8),
            boxShadow: _isOpen
                ? [
                    BoxShadow(
                      color: AppColors.primaryBlue.withValues(alpha: 0.08),
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
                color: iconColor,
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
                    color: textColor,
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
                  color: iconColor,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF111827) : Colors.white;
    final border = isDark ? const Color(0xFF334155) : Colors.grey.shade200;
    final divider = isDark ? const Color(0xFF1F2937) : Colors.grey.shade100;
    final searchBorder =
        isDark ? const Color(0xFF334155) : Colors.grey.shade300;
    final searchHint =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFFBBBBBB);
    final emptyText =
        isDark ? const Color(0xFF94A3B8) : const Color(0xFF9E9E9E);
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
                color: surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
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
                        hintStyle: TextStyle(fontSize: 13, color: searchHint),
                        prefixIcon: const Icon(Icons.search, size: 17),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 9),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(color: searchBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: const BorderSide(
                              color: AppColors.primaryBlue, width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(7),
                          borderSide: BorderSide(color: searchBorder),
                        ),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: divider),
                  // "All Sheets" row
                  _DropdownItem(
                    label: 'All Sheets',
                    selected: _local.isEmpty,
                    isAll: true,
                    onTap: () => _toggle(-1),
                  ),
                  Divider(height: 1, color: divider),
                  // Scrollable sheet list
                  SizedBox(
                    height: listH,
                    child: filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No sheets found',
                              style: TextStyle(fontSize: 12, color: emptyText),
                            ),
                          )
                        : ListView.builder(
                            primary: false,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedBg = isDark
        ? AppColors.primaryBlue.withValues(alpha: 0.18)
        : AppColors.primaryBlue.withValues(alpha: 0.06);
    final iconOff = isDark ? const Color(0xFF64748B) : const Color(0xFFBDBDBD);
    final textOff = isDark ? const Color(0xFFE5E7EB) : const Color(0xFF202124);
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: selected ? selectedBg : Colors.transparent,
        child: Row(
          children: [
            Icon(
              selected
                  ? (isAll ? Icons.done_all_rounded : Icons.check_box_rounded)
                  : (isAll
                      ? Icons.layers_outlined
                      : Icons.check_box_outline_blank_rounded),
              size: 17,
              color: selected ? AppColors.primaryBlue : iconOff,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? AppColors.primaryBlue : textOff,
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF5F6368);
    final textPrimary =
        isDark ? const Color(0xFFE2E8F0) : const Color(0xFF202124);
    final tableSurface = isDark ? const Color(0xFF111827) : Colors.white;
    final tableBorder =
        isDark ? const Color(0xFF334155) : _kBorder.withOpacity(0.7);
    final tableHeader =
        isDark ? const Color(0xFF0F172A) : const Color(0xFFF4F7FB);
    final divider = isDark ? const Color(0xFF1F2937) : Colors.grey.shade100;
    final zebraDark =
        isDark ? const Color(0xFF0B1528) : const Color(0xFFFAFBFD);
    final outRowBg = isDark
        ? const Color(0xFF2A1217)
        : Colors.red.shade50.withValues(alpha: 0.45);
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.check_circle_outline,
                  size: 36, color: Colors.green.shade400),
              const SizedBox(height: 8),
              Text('All materials are sufficiently stocked',
                  style: TextStyle(color: textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: tableSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tableBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.20 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Table(
          border: TableBorder(
            horizontalInside: BorderSide(color: divider, width: 1),
          ),
          columnWidths: const {
            0: FlexColumnWidth(2.6),
            1: FlexColumnWidth(1.3),
            2: FlexColumnWidth(1.1),
            3: FlexColumnWidth(1.2),
            4: FlexColumnWidth(1.1),
            5: FlexColumnWidth(1.5),
            6: FlexColumnWidth(1.5),
          },
          children: [
            TableRow(
              decoration: BoxDecoration(color: tableHeader),
              children: const [
                _TH('Product Name'),
                _TH('QB Code'),
                _TH('Curr. Stock'),
                _TH('Maintaining'),
                _TH('Critical'),
                _TH('Risk Meter'),
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
                  ? outRowBg
                  : index.isEven
                      ? tableSurface
                      : zebraDark;
              final current = (item['current_stock'] as num?)?.toDouble() ?? 0;
              final maintaining =
                  (item['maintaining_qty'] as num?)?.toDouble() ?? 0;
              final critical = (item['critical_qty'] as num?)?.toDouble() ?? 0;
              final qbCode =
                  (item['qb_code'] ?? item['qc_code'] ?? '-').toString();

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
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _TD(
                    child: Text(
                      qbCode,
                      style: TextStyle(
                        fontSize: 12,
                        color: textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _TD(
                    child: Text(
                      '${current.toInt()}',
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
                      '${maintaining.toInt()}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Color(0xFF9CA3AF) : Color(0xFF5F6368),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _TD(
                    child: Text(
                      '${critical.toInt()}',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Color(0xFF9CA3AF) : Color(0xFF5F6368),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  _TD(
                    child: _StockRiskBar(
                      currentStock: current,
                      maintaining: maintaining,
                      critical: critical,
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

class _StockRiskBar extends StatelessWidget {
  final double currentStock;
  final double maintaining;
  final double critical;

  const _StockRiskBar({
    required this.currentStock,
    required this.maintaining,
    required this.critical,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseline =
        maintaining <= 0 ? (critical <= 0 ? 1 : critical) : maintaining;
    final ratio = (currentStock / baseline).clamp(0.0, 1.0);
    final barColor = ratio <= 0.35
        ? const Color(0xFFEF4444)
        : (ratio <= 0.7 ? const Color(0xFFF59E0B) : const Color(0xFF22C55E));

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: 8,
        backgroundColor:
            isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB),
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475467),
          letterSpacing: 0.3,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        color: color.withValues(alpha: isDark ? 0.20 : 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: color.withValues(alpha: isDark ? 0.55 : 0.4), width: 1),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}
