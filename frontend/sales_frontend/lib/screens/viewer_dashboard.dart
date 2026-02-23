import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'sheet_screen.dart';

/// Viewer Module - For users with viewer role
/// Viewers can ONLY view Excel sheets and settings (NO dashboard, NO editing)
class ViewerDashboard extends StatefulWidget {
  const ViewerDashboard({super.key});

  @override
  State<ViewerDashboard> createState() => _ViewerDashboardState();
}

class _ViewerDashboardState extends State<ViewerDashboard> {
  bool _showSettings = false;

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      body: Column(
        children: [
          // Top App Bar - Simple header with user info and settings
          Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                // App Title
                Icon(
                  Icons.visibility,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  'Sheet Viewer',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const Spacer(),

                // Real-time updates indicator
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withOpacity(0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Live Updates',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Read-only badge
                Chip(
                  avatar: const Icon(Icons.lock, size: 16),
                  label: const Text('Read-Only'),
                  labelStyle: const TextStyle(fontSize: 12),
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                ),
                const SizedBox(width: 16),

                // User info
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  child: Text(
                    auth.user?.username[0].toUpperCase() ?? 'V',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user?.fullName ?? auth.user?.username ?? 'Viewer',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      'Viewer',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),

                // Settings button
                IconButton(
                  icon: const Icon(Icons.settings_outlined),
                  tooltip: 'Settings',
                  onPressed: () {
                    setState(() => _showSettings = !_showSettings);
                  },
                ),

                // Logout button
                IconButton(
                  icon: const Icon(Icons.logout),
                  tooltip: 'Logout',
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
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Logout'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true && context.mounted) {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
          ),

          // Settings Panel (collapsible)
          if (_showSettings)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Settings',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        iconSize: 20,
                        onPressed: () => setState(() => _showSettings = false),
                      ),
                    ],
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  _buildSettingItem(
                    context,
                    icon: Icons.person,
                    title: 'Username',
                    value: auth.user?.username ?? '',
                  ),
                  _buildSettingItem(
                    context,
                    icon: Icons.email,
                    title: 'Email',
                    value: auth.user?.email ?? '',
                  ),
                  _buildSettingItem(
                    context,
                    icon: Icons.badge,
                    title: 'Full Name',
                    value: auth.user?.fullName ?? 'N/A',
                  ),
                  _buildSettingItem(
                    context,
                    icon: Icons.business,
                    title: 'Department',
                    value: auth.user?.departmentName ?? 'N/A',
                  ),
                ],
              ),
            ),

          // Sheet content (read-only) - Direct access, no navigation
          const Expanded(
            child: SheetScreen(readOnly: true),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
