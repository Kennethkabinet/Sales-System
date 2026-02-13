import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import 'login_screen.dart';
import 'file_list_screen.dart';
import 'audit_history_screen.dart';
import 'sheet_screen.dart';
import 'user_management_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> with TickerProviderStateMixin {
  int _selectedIndex = 0;
  bool _isSidebarOpen = false;
  late AnimationController _sidebarController;
  late Animation<double> _sidebarAnimation;
  GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    
    // Initialize sidebar animation
    _sidebarController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _sidebarAnimation = CurvedAnimation(
      parent: _sidebarController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadDashboard();
    });
  }

  @override
  void dispose() {
    _sidebarController.dispose();
    super.dispose();
  }

  void _toggleSidebar() {
    setState(() {
      _isSidebarOpen = !_isSidebarOpen;
      if (_isSidebarOpen) {
        _sidebarController.forward();
      } else {
        _sidebarController.reverse();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final isAdmin = auth.user?.role == 'admin';

    final pages = [
      const _DashboardContent(),
      const SheetScreen(),
      const FileListScreen(),
      const AuditHistoryScreen(),
      if (isAdmin) const UserManagementScreen(),
    ];

    return Scaffold(
      key: _scaffoldKey,
      body: Stack(
        children: [
          // Main content with header
          Column(
            children: [
              // Custom header with hamburger button
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      offset: const Offset(0, 2),
                      blurRadius: 4,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Hamburger menu button
                    IconButton(
                      icon: AnimatedIcon(
                        icon: AnimatedIcons.menu_close,
                        progress: _sidebarAnimation,
                        size: 28,
                      ),
                      onPressed: _toggleSidebar,
                      tooltip: 'Toggle Menu',
                    ),
                    // App title
                    Expanded(
                      child: Row(
                        children: [
                          Icon(
                            Icons.inventory_2,
                            color: Theme.of(context).primaryColor,
                            size: 32,
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Sales System - Admin Dashboard',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // User info in header
                    Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
                                child: Text(
                                  (auth.user?.fullName ?? 'A')[0].toUpperCase(),
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    auth.user?.fullName ?? 'Admin',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    'Administrator',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              // Main content
              Expanded(
                child: pages[_selectedIndex],
              ),
            ],
          ),
          // Animated sidebar overlay
          AnimatedBuilder(
            animation: _sidebarAnimation,
            builder: (context, child) {
              return Stack(
                children: [
                  // Semi-transparent overlay
                  if (_sidebarAnimation.value > 0)
                    GestureDetector(
                      onTap: _toggleSidebar,
                      child: Container(
                        color: Colors.black.withOpacity(0.3 * _sidebarAnimation.value),
                      ),
                    ),
                  // Sidebar
                  Transform.translate(
                    offset: Offset(-280 * (1 - _sidebarAnimation.value), 0),
                    child: Container(
                      width: 280,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            offset: const Offset(2, 0),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: _buildSidebarContent(auth, isAdmin),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarContent(AuthProvider auth, bool isAdmin) {
    final menuItems = [
      _SidebarItem(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Dashboard',
        index: 0,
      ),
      _SidebarItem(
        icon: Icons.grid_on_outlined,
        selectedIcon: Icons.grid_on,
        label: 'Sheet',
        index: 1,
      ),
      _SidebarItem(
        icon: Icons.folder_outlined,
        selectedIcon: Icons.folder,
        label: 'Files',
        index: 2,
      ),
      _SidebarItem(
        icon: Icons.history_outlined,
        selectedIcon: Icons.history,
        label: 'Audit Log',
        index: 3,
      ),
      if (isAdmin)
        _SidebarItem(
          icon: Icons.people_outlined,
          selectedIcon: Icons.people,
          label: 'Users',
          index: 4,
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar header
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor,
                Theme.of(context).primaryColor.withOpacity(0.8),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.inventory_2,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Sales System',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Administration Panel',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.8),
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
        // Menu items
        Expanded(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              const SizedBox(height: 8),
              ...menuItems.map((item) => _buildSidebarMenuItem(item)),
              const SizedBox(height: 16),
              const Divider(),
            ],
          ),
        ),
        // Profile and logout section
        Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // Profile section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: Theme.of(context).primaryColor,
                      child: Text(
                        (auth.user?.fullName ?? 'A')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            auth.user?.fullName ?? 'Administrator',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            auth.user?.role?.toUpperCase() ?? 'ADMIN',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.secondary,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Logout button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Logout'),
                        content: const Text('Are you sure you want to logout?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    
                    if (confirmed == true) {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.withOpacity(0.1),
                    foregroundColor: Colors.red,
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidebarMenuItem(_SidebarItem item) {
    final isSelected = _selectedIndex == item.index;
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        leading: Icon(
          isSelected ? item.selectedIcon : item.icon,
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
        ),
        title: Text(
          item.label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected 
                ? Theme.of(context).primaryColor 
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        selected: isSelected,
        selectedTileColor: Theme.of(context).primaryColor.withOpacity(0.1),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        onTap: () {
          setState(() {
            _selectedIndex = item.index;
          });
          _toggleSidebar(); // Close sidebar after selection
        },
      ),
    );
  }
}

class _SidebarItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int index;

  _SidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.index,
  });
}

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
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Dashboard Overview',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => data.loadDashboard(),
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh Data',
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Stats cards
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    _StatCard(
                      title: 'Total Files',
                      value: stats?.totalFiles.toString() ?? '0',
                      icon: Icons.folder,
                      color: Colors.blue,
                    ),
                    _StatCard(
                      title: 'Total Records',
                      value: stats?.totalRecords.toString() ?? '0',
                      icon: Icons.table_rows,
                      color: Colors.green,
                    ),
                    _StatCard(
                      title: 'Active Users',
                      value: stats?.activeUsers.toString() ?? '0',
                      icon: Icons.people,
                      color: Colors.orange,
                    ),
                    _StatCard(
                      title: 'Recent Changes',
                      value: stats?.recentChanges.toString() ?? '0',
                      icon: Icons.edit,
                      color: Colors.purple,
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Charts row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Activity chart
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
                    // File types
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
                const SizedBox(height: 32),

                // Recent activity table
                _ChartCard(
                  title: 'Recent Activity',
                  child: stats != null && stats.recentActivity.isNotEmpty
                      ? _RecentActivityTable(activities: stats.recentActivity)
                      : const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: Text('No recent activity')),
                        ),
                ),
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

  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey[600],
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
}

class _ChartCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ChartCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
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
