import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import '../providers/auth_provider.dart';
import '../providers/data_provider.dart';
import 'login_screen.dart';
import 'file_list_screen.dart';
import 'formula_list_screen.dart';
import 'audit_history_screen.dart';
import 'sheet_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DataProvider>().loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      const _DashboardContent(),
      const SheetScreen(),
      const FileListScreen(),
      const FormulaListScreen(),
      const AuditHistoryScreen(),
    ];

    return Scaffold(
      body: Row(
        children: [
          // Sidebar
          NavigationRail(
            extended: true,
            minExtendedWidth: 200,
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) {
              setState(() => _selectedIndex = index);
            },
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2, color: Theme.of(context).primaryColor, size: 32),
                  const SizedBox(width: 8),
                  const Text(
                    'Sales System',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            trailing: Consumer<AuthProvider>(
              builder: (context, auth, _) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Divider(),
                      CircleAvatar(
                        child: Text(
                          (auth.user?.fullName ?? 'U').substring(0, 1).toUpperCase(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        auth.user?.fullName ?? 'User',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        auth.user?.role ?? '',
                        style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () async {
                          await auth.logout();
                          if (context.mounted) {
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(builder: (_) => const LoginScreen()),
                            );
                          }
                        },
                        icon: const Icon(Icons.logout, size: 18),
                        label: const Text('Logout'),
                      ),
                    ],
                  ),
                );
              },
            ),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: Text('Dashboard'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.grid_on_outlined),
                selectedIcon: Icon(Icons.grid_on),
                label: Text('Sheet'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.folder_outlined),
                selectedIcon: Icon(Icons.folder),
                label: Text('Files'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.functions_outlined),
                selectedIcon: Icon(Icons.functions),
                label: Text('Formulas'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history_outlined),
                selectedIcon: Icon(Icons.history),
                label: Text('Audit Log'),
              ),
            ],
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // Main content
          Expanded(
            child: pages[_selectedIndex],
          ),
        ],
      ),
    );
  }
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
                      'Dashboard',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      onPressed: () => data.loadDashboard(),
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Refresh',
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
