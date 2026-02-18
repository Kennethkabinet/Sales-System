import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import '../services/api_service.dart';
import 'login_screen.dart';
import 'file_list_screen.dart';
import 'audit_history_screen.dart';
import 'sheet_screen.dart';
import 'user_management_screen.dart';

// ─── Theme colors ───
const Color _kSidebarBg = Color(0xFFCD5C5C);
const Color _kContentBg = Color(0xFFFDF5F0);
const Color _kNavy = Color(0xFF1E3A6E);
const Color _kBlue = Color(0xFF3B5998);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  bool _sidebarExpanded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isAdmin = auth.user?.role == 'admin';
    final isViewer = auth.user?.role == 'viewer';

    // Build pages list
    final pages = <Widget>[
      const _DashboardContent(),
      const SheetScreen(),
      if (!isViewer) const FileListScreen(),
      const AuditHistoryScreen(),
      if (isAdmin) const UserManagementScreen(),
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
    navItems.add(_NavItem(Icons.settings, 'Settings', -1)); // placeholder

    return Scaffold(
      backgroundColor: _kContentBg,
      body: Row(
        children: [
          // ── Sidebar ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: _sidebarExpanded ? 220 : 68,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(color: _kSidebarBg),
            child: Column(
              children: [
                // Hamburger
                Container(
                  height: 56,
                  alignment: _sidebarExpanded
                      ? Alignment.centerLeft
                      : Alignment.center,
                  padding: EdgeInsets.only(
                    left: _sidebarExpanded ? 16 : 0,
                    top: 8,
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.menu, color: Colors.white, size: 26),
                    onPressed: () =>
                        setState(() => _sidebarExpanded = !_sidebarExpanded),
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
                    height: 60,
                    color: _kContentBg,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _currentTitle,
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: _kNavy,
                        letterSpacing: 0.5,
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
        return 'ADMIN DASHBOARD';
      case 1:
        return 'WORK SHEETS';
      default:
        return 'ADMIN DASHBOARD';
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
        color: Colors.white.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: Colors.grey[300],
            child: Icon(Icons.person, color: Colors.grey[600], size: 24),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (auth.user?.fullName ?? 'ADMINISTRATOR').toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  auth.user?.role ?? 'Administrator',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.8),
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
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (item.index >= 0) {
              setState(() => _selectedIndex = item.index);
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
                  color: selected ? _kSidebarBg : Colors.white,
                  size: 22,
                ),
                if (_sidebarExpanded) ...[
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        color: selected ? _kSidebarBg : Colors.white,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14,
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
                    backgroundColor: _kSidebarBg,
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
              const Icon(Icons.logout, color: Colors.white, size: 22),
              if (_sidebarExpanded) ...[
                const SizedBox(width: 14),
                const Text(
                  'Logout',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
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
class _DashboardContent extends StatelessWidget {
  const _DashboardContent();

  @override
  Widget build(BuildContext context) {
    return Consumer<DataProvider>(
      builder: (context, data, _) {
        if (data.isLoading && data.dashboardStats == null) {
          return const Center(child: CircularProgressIndicator());
        }

        final stats = data.dashboardStats;

        return RefreshIndicator(
          onRefresh: () => data.loadDashboard(),
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats cards row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cardWidth =
                        (constraints.maxWidth - 48) / 4; // 3 gaps × 16
                    return Row(
                      children: [
                        _StatCard(
                          title: 'Total Files',
                          value: stats?.totalFiles.toString() ?? '0',
                          icon: Icons.folder_outlined,
                          color: _kNavy,
                          width: cardWidth,
                        ),
                        const SizedBox(width: 16),
                        _StatCard(
                          title: 'Total Records',
                          value: stats?.totalRecords.toString() ?? '0',
                          icon: Icons.menu,
                          color: _kNavy,
                          width: cardWidth,
                        ),
                        const SizedBox(width: 16),
                        _StatCard(
                          title: 'Active Users',
                          value: stats?.activeUsers.toString() ?? '0',
                          icon: Icons.people_alt_outlined,
                          color: _kNavy,
                          width: cardWidth,
                        ),
                        const SizedBox(width: 16),
                        _StatCard(
                          title: 'Recent Changes',
                          value: stats?.recentChanges.toString() ?? '0',
                          icon: Icons.edit_outlined,
                          color: _kNavy,
                          width: cardWidth,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Charts row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: _ChartCard(
                        title: 'Activity (Last 7 Days)',
                        child: SizedBox(
                          height: 250,
                          child: stats != null && stats.activityData.isNotEmpty
                              ? _ActivityChart(data: stats.activityData)
                              : const Center(child: Text('No activity data')),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ChartCard(
                        title: 'Files by Type',
                        child: SizedBox(
                          height: 250,
                          child: stats != null && stats.fileTypes.isNotEmpty
                              ? _FileTypesChart(data: stats.fileTypes)
                              : const Center(child: Text('No files')),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Recent activity
                _ChartCard(
                  title: 'Recent Activity',
                  child: stats != null && stats.recentActivity.isNotEmpty
                      ? _RecentActivityTable(
                          activities: stats.recentActivity)
                      : const Padding(
                          padding: EdgeInsets.all(32),
                          child:
                              Center(child: Text('No recent activity')),
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
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final double width;

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                    color: color,
                  ),
                ),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _kNavy,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _ActivityChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _ActivityChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final spots = data.asMap().entries.map((entry) {
      return FlSpot(
        entry.key.toDouble(),
        (entry.value['count'] as num?)?.toDouble() ?? 0,
      );
    }).toList();

    return LineChart(
      LineChartData(
        gridData: FlGridData(show: true, drawVerticalLine: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) => Text(value.toInt().toString()),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < data.length) {
                  final date = data[index]['date']?.toString() ?? '';
                  return Text(
                    date.length > 5 ? date.substring(5) : date,
                    style: const TextStyle(fontSize: 10),
                  );
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: Theme.of(context).primaryColor,
            barWidth: 3,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: Theme.of(context).primaryColor.withOpacity(0.1),
            ),
          ),
        ],
      ),
    );
  }
}

class _FileTypesChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _FileTypesChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red];
    
    return PieChart(
      PieChartData(
        sections: data.asMap().entries.map((entry) {
          final item = entry.value;
          return PieChartSectionData(
            value: (item['count'] as num?)?.toDouble() ?? 0,
            title: item['type']?.toString() ?? '',
            color: colors[entry.key % colors.length],
            radius: 80,
            titleStyle: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          );
        }).toList(),
        sectionsSpace: 2,
        centerSpaceRadius: 30,
      ),
    );
  }
}

class _RecentActivityTable extends StatelessWidget {
  final List<Map<String, dynamic>> activities;

  const _RecentActivityTable({required this.activities});

  @override
  Widget build(BuildContext context) {
    return DataTable(
      columns: const [
        DataColumn(label: Text('User')),
        DataColumn(label: Text('Action')),
        DataColumn(label: Text('Target')),
        DataColumn(label: Text('Time')),
      ],
      rows: activities.take(10).map((activity) {
        return DataRow(cells: [
          DataCell(Text(activity['user']?.toString() ?? '-')),
          DataCell(_ActionChip(action: activity['action']?.toString() ?? '')),
          DataCell(Text(activity['target']?.toString() ?? '-')),
          DataCell(Text(_formatTime(activity['timestamp']?.toString()))),
        ]);
      }).toList(),
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '-';
    try {
      final dt = DateTime.parse(timestamp);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return timestamp;
    }
  }
}

class _ActiveUsersList extends StatelessWidget {
  final List<DashboardActiveUser> users;

  const _ActiveUsersList({required this.users});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: users.map((user) {
        return ListTile(
          leading: CircleAvatar(
            backgroundColor: _getRoleColor(user.role).withOpacity(0.15),
            child: Text(
              _getInitials(user.fullName.isNotEmpty ? user.fullName : user.username),
              style: TextStyle(
                color: _getRoleColor(user.role),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          title: Text(
            user.fullName.isNotEmpty ? user.fullName : user.username,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(user.email),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _getRoleColor(user.role).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  user.role.toUpperCase(),
                  style: TextStyle(
                    color: _getRoleColor(user.role),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.green.withOpacity(0.4),
                      blurRadius: 4,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatLastLogin(user.lastLogin),
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return Colors.red;
      case 'editor':
        return Colors.blue;
      case 'viewer':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _formatLastLogin(String? lastLogin) {
    if (lastLogin == null) return 'N/A';
    try {
      final dt = DateTime.parse(lastLogin);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return '${diff.inDays}d ago';
    } catch (_) {
      return 'N/A';
    }
  }
}

class _ActionChip extends StatelessWidget {
  final String action;

  const _ActionChip({required this.action});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (action.toLowerCase()) {
      case 'create':
        color = Colors.green;
        break;
      case 'update':
        color = Colors.blue;
        break;
      case 'delete':
        color = Colors.red;
        break;
      default:
        color = Colors.grey;
    }

    return Chip(
      label: Text(
        action,
        style: TextStyle(color: color, fontSize: 12),
      ),
      backgroundColor: color.withOpacity(0.1),
      padding: EdgeInsets.zero,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
