import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'sheet_screen.dart';

/// Editor Module - For users with editor role
/// Editors can ONLY access Excel sheets and settings (NO dashboard)
class EditorDashboard extends StatefulWidget {
  const EditorDashboard({super.key});

  @override
  State<EditorDashboard> createState() => _EditorDashboardState();
}

class _EditorDashboardState extends State<EditorDashboard> {
  bool _showSettings = false;

  static const Color _kAccent = Color(0xFF1A73E8);
  static const Color _kNavy = Color(0xFF202124);
  static const Color _kGray = Color(0xFF5F6368);
  static const Color _kBg = Color(0xFFFFFFFF);
  static const Color _kBorder = Color(0xFFE8EAED);
  static const Color _kAvatBg = Color(0xFFE8F0FE);

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);

    return Scaffold(
      backgroundColor: _kBg,
      body: Column(
        children: [
          // ── Top bar ──
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: const BoxDecoration(
              color: _kBg,
              border: Border(
                bottom: BorderSide(color: Color(0xFFE8EAED)),
              ),
            ),
            child: Row(
              children: [
                // App Title
                const Icon(Icons.edit_document, size: 22, color: _kAccent),
                const SizedBox(width: 10),
                const Text(
                  'Sheet Editor',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _kNavy,
                  ),
                ),
                const Spacer(),

                // Live Sync badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE6F4EA),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Color(0xFF34A853),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Live Sync',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF1E7E34),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Edit mode badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kAvatBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.edit, size: 13, color: _kAccent),
                      SizedBox(width: 5),
                      Text(
                        'Edit Mode',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: _kAccent,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // User info
                CircleAvatar(
                  radius: 17,
                  backgroundColor: _kAvatBg,
                  child: Text(
                    auth.user?.username[0].toUpperCase() ?? 'E',
                    style: const TextStyle(
                      color: _kAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      auth.user?.fullName ?? auth.user?.username ?? 'Editor',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kNavy,
                      ),
                    ),
                    const Text(
                      'Editor',
                      style: TextStyle(fontSize: 11, color: _kGray),
                    ),
                  ],
                ),
                const SizedBox(width: 8),

                // Settings button
                IconButton(
                  icon: const Icon(Icons.settings_outlined, color: _kGray),
                  tooltip: 'Settings',
                  onPressed: () {
                    setState(() => _showSettings = !_showSettings);
                  },
                ),

                // Logout button
                IconButton(
                  icon: const Icon(Icons.logout, color: _kGray),
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
              decoration: const BoxDecoration(
                color: Color(0xFFF8F9FA),
                border: Border(
                  bottom: BorderSide(color: _kBorder),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.settings, size: 18, color: _kAccent),
                      const SizedBox(width: 8),
                      const Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _kNavy,
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

          // Sheet content - Direct access, no navigation
          const Expanded(
            child: SheetScreen(),
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
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Icon(icon, size: 16, color: _kAccent),
          const SizedBox(width: 12),
          SizedBox(
            width: 110,
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, color: _kGray),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _kNavy,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
