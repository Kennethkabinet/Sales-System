import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../config/constants.dart';
import 'login_screen.dart';
import 'sheet_screen.dart';
import 'settings_screen.dart';

/// Editor Module - For users with editor role
/// Editors can ONLY access Excel sheets and settings (NO dashboard)
class EditorDashboard extends StatefulWidget {
  const EditorDashboard({super.key});

  @override
  State<EditorDashboard> createState() => _EditorDashboardState();
}

class _EditorDashboardState extends State<EditorDashboard> {
  int _selectedIndex = 0; // 0 = Sheets, 1 = Settings

  static const Color _kGray = Color(0xFF6B7280);
  static const Color _kBg = Color(0xFFF9FAFB);
  static const Color _kBorder = Color(0xFFE5E7EB);
  static const Color _kBlue = Color(0xFF4285F4);

  String _getInitials(String? fullName, String? username) {
    if (fullName != null && fullName.trim().isNotEmpty) {
      final parts = fullName.trim().split(' ');
      if (parts.length >= 2) {
        return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
      } else if (parts.isNotEmpty) {
        return parts.first[0].toUpperCase();
      }
    }
    if (username != null && username.isNotEmpty) {
      return username[0].toUpperCase();
    }
    return 'E';
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pageBg = isDark ? const Color(0xFF111827) : _kBg;
    final surfaceBg = isDark ? const Color(0xFF1F2937) : Colors.white;
    final borderColor = isDark ? const Color(0xFF374151) : _kBorder;
    final textPrimary =
        isDark ? const Color(0xFFF3F4F6) : const Color(0xFF1F2937);
    final textMuted =
        isDark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final searchBg = isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);
    final user = auth.user;
    final initials = _getInitials(user?.fullName, user?.username);

    return Scaffold(
      backgroundColor: pageBg,
      body: Row(
        children: [
          // ── Sidebar ──
          Container(
            width: 220,
            decoration: BoxDecoration(
              color: surfaceBg,
              border: Border(right: BorderSide(color: borderColor)),
            ),
            child: Column(
              children: [
                // Header
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
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
                    ],
                  ),
                ),

                // User profile card
                Container(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: searchBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: _kBlue,
                        child: Text(
                          initials,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.fullName ?? user?.username ?? 'Editor',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              'Editor',
                              style: TextStyle(
                                color: textMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Nav items
                _buildNavItem(Icons.apps, 'Work Sheets', 0),
                _buildNavItem(Icons.settings_outlined, 'Settings', 1),

                const Spacer(),

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
                // Top bar - HireGround style
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: surfaceBg,
                    border: Border(
                        bottom:
                            BorderSide(color: borderColor.withOpacity(0.8))),
                  ),
                  child: Row(
                    children: [
                      Text(
                        _selectedIndex == 0 ? 'Work Sheets' : 'Settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const Spacer(),
                      // Search bar
                      Container(
                        width: 300,
                        height: 38,
                        decoration: BoxDecoration(
                          color: searchBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(width: 12),
                            Icon(Icons.search, size: 18, color: textMuted),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('Search',
                                  style: TextStyle(
                                      fontSize: 13, color: textMuted)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                color: surfaceBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: borderColor),
                              ),
                              child: Text('Ctrl+K',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: textMuted)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      _HeaderIconButton(
                        icon: themeProvider.isDarkMode
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        onTap: () =>
                            context.read<ThemeProvider>().toggleTheme(),
                      ),
                      const SizedBox(width: 8),
                      _HeaderIconButton(
                          icon: Icons.notifications_none_outlined,
                          onTap: () {}),
                      const SizedBox(width: 16),
                      // User profile in header
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _kBlue,
                            child: Text(initials,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white)),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(user?.fullName ?? user?.username ?? 'Editor',
                                  style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: textPrimary)),
                              Text('Editor',
                                  style: TextStyle(
                                      fontSize: 11, color: textMuted)),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Icon(Icons.keyboard_arrow_down,
                              size: 18, color: textMuted),
                        ],
                      ),
                    ],
                  ),
                ),

                // Page content
                Expanded(
                  child: _selectedIndex == 0
                      ? const SheetScreen()
                      : const SettingsScreen(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, int index) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor =
        isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6);
    final selectedBg =
        isDark ? const Color(0xFF1E3A8A) : const Color(0xFFE8F0FE);
    final inactive = isDark ? const Color(0xFFD1D5DB) : _kGray;
    final selected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? selectedBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: hoverColor,
          onTap: () => setState(() => _selectedIndex = index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, color: selected ? _kBlue : inactive, size: 20),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    color: selected ? _kBlue : inactive,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton(AuthProvider auth) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hoverColor =
        isDark ? const Color(0xFF374151) : const Color(0xFFF3F4F6);
    final textColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          hoverColor: hoverColor,
          onTap: () async {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Logout'),
                content: const Text('Are you sure you want to logout?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryRed,
                        foregroundColor: Colors.white),
                    child: const Text('Logout'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await auth.logout();
              if (mounted) {
                Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()));
              }
            }
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.logout, color: textColor, size: 20),
                const SizedBox(width: 12),
                Text('Logout',
                    style: TextStyle(color: textColor, fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _HeaderIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF111827) : const Color(0xFFF9FAFB);
    final border = isDark ? const Color(0xFF374151) : const Color(0xFFE5E7EB);
    final iconColor =
        isDark ? const Color(0xFFD1D5DB) : const Color(0xFF6B7280);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 18, color: iconColor),
      ),
    );
  }
}
