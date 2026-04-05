import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../config/constants.dart';

const Color _kPrimaryBlue = Color(0xFF4285F4);
const Color _kNavy = Color(0xFF1F2937);
const Color _kGray = Color(0xFF6B7280);
const Color _kLightGray = Color(0xFF9CA3AF);
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kBg = Color(0xFFF3F4F6);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor => _isDark ? const Color(0xFF0B1220) : _kBg;
  Color get _surfaceColor => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _borderColor => _isDark ? const Color(0xFF334155) : _kBorder;
  Color get _textPrimary => _isDark ? const Color(0xFFE5E7EB) : _kNavy;
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : _kGray;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    return 'U';
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;

    return Scaffold(
      backgroundColor: _bgColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Main content card - expands to fill remaining space
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Blue gradient banner
                        _buildBanner(),

                        // Profile and content area - expands to fill
                        Expanded(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Left profile sidebar
                              _buildProfileSidebar(user),

                              // Right content area with tabs
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Tab bar
                                    Container(
                                      decoration: BoxDecoration(
                                        border: Border(
                                          bottom:
                                              BorderSide(color: _borderColor),
                                        ),
                                      ),
                                      child: TabBar(
                                        controller: _tabController,
                                        labelColor: _kPrimaryBlue,
                                        unselectedLabelColor: _textSecondary,
                                        indicatorColor: _kPrimaryBlue,
                                        indicatorWeight: 2,
                                        labelStyle: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        unselectedLabelStyle: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w400,
                                        ),
                                        isScrollable: true,
                                        tabAlignment: TabAlignment.start,
                                        tabs: const [
                                          Tab(text: 'Account Settings'),
                                          Tab(text: 'Security'),
                                          Tab(text: 'System Status'),
                                          Tab(text: 'About'),
                                        ],
                                      ),
                                    ),

                                    // Tab content - expands to fill
                                    Expanded(
                                      child: TabBarView(
                                        controller: _tabController,
                                        children: [
                                          _AccountTab(auth: auth),
                                          _SecurityTab(auth: auth),
                                          const _SystemTab(),
                                          const _AboutTab(),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBanner() {
    return Container(
      height: 120,
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF5C6BC0),
            Color(0xFF3949AB),
            Color(0xFF303F9F),
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(painter: _BannerPatternPainter()),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSidebar(user) {
    final initials = _getInitials(user?.fullName, user?.username);

    return Container(
      width: 260,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: _borderColor)),
      ),
      child: Column(
        children: [
          // Profile avatar overlapping banner with initials
          Transform.translate(
            offset: const Offset(0, -50),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: CircleAvatar(
                radius: 50,
                backgroundColor: _kPrimaryBlue,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Name and role
          Transform.translate(
            offset: const Offset(0, -30),
            child: Column(
              children: [
                Text(
                  user?.fullName ?? user?.username ?? 'User',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.email ?? 'No email set',
                  style: TextStyle(fontSize: 13, color: _textSecondary),
                ),
                const SizedBox(height: 16),

                // Stats
                _buildStatRow('Username', user?.username ?? '-'),
                _buildStatRow('Role', user?.role ?? 'User'),
                _buildStatRow(
                    'Status', user?.isActive == true ? 'Active' : 'Inactive'),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13, color: _textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: label == 'Status' && value == 'Active'
                  ? const Color(0xFF34A853)
                  : _kPrimaryBlue,
            ),
          ),
        ],
      ),
    );
  }
}

// Banner pattern painter
class _BannerPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.1)
      ..style = PaintingStyle.fill;

    final path1 = Path()
      ..moveTo(size.width * 0.7, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.6)
      ..close();
    canvas.drawPath(path1, paint);

    final path2 = Path()
      ..moveTo(size.width * 0.5, size.height)
      ..lineTo(size.width * 0.8, size.height)
      ..lineTo(size.width * 0.65, size.height * 0.4)
      ..close();
    canvas.drawPath(path2, paint..color = Colors.white.withValues(alpha: 0.05));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ═══════════════════════════════════════════════════════
//  ACCOUNT TAB
// ═══════════════════════════════════════════════════════
class _AccountTab extends StatefulWidget {
  final AuthProvider auth;
  const _AccountTab({required this.auth});

  @override
  State<_AccountTab> createState() => _AccountTabState();
}

class _AccountTabState extends State<_AccountTab> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _usernameCtrl;
  bool _saving = false;
  String? _message;
  bool _success = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _dialogSurface => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _fieldFill => _isDark ? const Color(0xFF0F172A) : Colors.white;
  Color get _readOnlyFill => _isDark ? const Color(0xFF1F2937) : _kBg;
  Color get _labelColor => _isDark ? const Color(0xFFCBD5E1) : _kNavy;
  Color get _hintColor => _isDark ? const Color(0xFF94A3B8) : _kLightGray;
  Color get _fieldBorder => _isDark ? const Color(0xFF334155) : _kBorder;

  @override
  void initState() {
    super.initState();
    final u = widget.auth.user;
    // Split fullName into first and last name
    final nameParts = (u?.fullName ?? '').trim().split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts.first : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    _firstNameCtrl = TextEditingController(text: firstName);
    _lastNameCtrl = TextEditingController(text: lastName);
    _emailCtrl = TextEditingController(text: u?.email ?? '');
    _usernameCtrl = TextEditingController(text: u?.username ?? '');
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    super.dispose();
  }

  Future<void> _promptPasswordAndSave() async {
    if (!_formKey.currentState!.validate()) return;

    final passwordCtrl = TextEditingController();
    bool obscurePassword = true;
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: _dialogSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: _fieldBorder),
          ),
          title: Row(
            children: [
              const Icon(Icons.lock_outline, color: _kPrimaryBlue, size: 24),
              const SizedBox(width: 12),
              Text('Confirm Password',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _labelColor)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Please enter your current password to confirm changes.',
                style: TextStyle(fontSize: 13, color: _hintColor),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscurePassword,
                autofocus: true,
                style: TextStyle(fontSize: 14, color: _labelColor),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(fontSize: 13, color: _hintColor),
                  errorText: errorText,
                  filled: true,
                  fillColor: _fieldFill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _fieldBorder),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: BorderSide(color: _fieldBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide:
                        const BorderSide(color: _kPrimaryBlue, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: _hintColor,
                      size: 20,
                    ),
                    onPressed: () => setDialogState(
                        () => obscurePassword = !obscurePassword),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: _hintColor)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (passwordCtrl.text.isEmpty) {
                  setDialogState(() => errorText = 'Password is required');
                  return;
                }
                // Verify password by attempting login
                try {
                  await ApiService.login(
                    widget.auth.user!.username,
                    passwordCtrl.text,
                  );
                  if (!ctx.mounted) return;
                  Navigator.pop(ctx, true);
                } catch (e) {
                  setDialogState(() => errorText = 'Incorrect password');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimaryBlue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ),
    );

    passwordCtrl.dispose();

    if (confirmed == true) {
      await _save();
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final u = widget.auth.user!;
      // Combine first and last name
      final fullName =
          '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();

      await ApiService.updateUser(
        userId: u.id,
        fullName: fullName,
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
      );
      // Refresh user data
      await widget.auth.refreshUser();
      setState(() {
        _saving = false;
        _success = true;
        _message = 'Profile updated successfully.';
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _success = false;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.auth.user;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Two-column form layout - First Name and Last Name
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildFormField(
                    label: 'First Name',
                    controller: _firstNameCtrl,
                    hint: 'Enter your first name',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildFormField(
                    label: 'Last Name',
                    controller: _lastNameCtrl,
                    hint: 'Enter your last name',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Username and Email
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildFormField(
                    label: 'Username',
                    controller: _usernameCtrl,
                    hint: 'Enter your username',
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildFormField(
                    label: 'Email Address',
                    controller: _emailCtrl,
                    hint: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (!v.contains('@')) return 'Enter a valid email';
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Role (read-only)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildFormField(
                    label: 'Role',
                    controller: TextEditingController(text: u?.role ?? 'User'),
                    readOnly: true,
                  ),
                ),
                const Expanded(child: SizedBox()), // Empty space for alignment
              ],
            ),
            const SizedBox(height: 24),
            if (_message != null) ...[
              _MessageBanner(message: _message!, success: _success),
              const SizedBox(height: 16),
            ],
            _UpdateButton(saving: _saving, onPressed: _promptPasswordAndSave),
          ],
        ),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required TextEditingController controller,
    String? hint,
    bool readOnly = false,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _labelColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          readOnly: readOnly,
          keyboardType: keyboardType,
          validator: validator,
          style: TextStyle(fontSize: 14, color: _labelColor),
          decoration: InputDecoration(
            hintText: hint ?? '',
            hintStyle: TextStyle(fontSize: 14, color: _hintColor),
            filled: true,
            fillColor: readOnly ? _readOnlyFill : _fieldFill,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                  color: readOnly ? _fieldBorder : _fieldBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _kPrimaryBlue, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFEA4335)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  const BorderSide(color: Color(0xFFEA4335), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECURITY TAB
// ═══════════════════════════════════════════════════════
class _SecurityTab extends StatefulWidget {
  final AuthProvider auth;
  const _SecurityTab({required this.auth});

  @override
  State<_SecurityTab> createState() => _SecurityTabState();
}

class _SecurityTabState extends State<_SecurityTab> {
  final _formKey = GlobalKey<FormState>();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  bool _saving = false;
  String? _message;
  bool _success = false;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final u = widget.auth.user!;
      await ApiService.updateUser(
        userId: u.id,
        password: _newPassCtrl.text.trim(),
      );
      _newPassCtrl.clear();
      _confirmPassCtrl.clear();
      setState(() {
        _saving = false;
        _success = true;
        _message = 'Password changed successfully.';
      });
    } catch (e) {
      setState(() {
        _saving = false;
        _success = false;
        _message = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final infoBg = isDark
        ? const Color(0xFF1E3A8A).withValues(alpha: 0.20)
        : const Color(0xFFE8F0FE);
    final infoText = isDark ? const Color(0xFFBFDBFE) : _kPrimaryBlue;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info card
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: infoText),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Use a strong password of at least 8 characters with a mix of letters and numbers.',
                      style: TextStyle(fontSize: 12, color: infoText),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildPasswordField(
                    label: 'New Password',
                    controller: _newPassCtrl,
                    hint: 'Enter new password',
                    obscure: _obscureNew,
                    onToggle: () => setState(() => _obscureNew = !_obscureNew),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (v.trim().length < 6) return 'At least 6 characters';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: _buildPasswordField(
                    label: 'Confirm New Password',
                    controller: _confirmPassCtrl,
                    hint: 'Confirm new password',
                    obscure: _obscureConfirm,
                    onToggle: () =>
                        setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) {
                      if (v != _newPassCtrl.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_message != null) ...[
              _MessageBanner(message: _message!, success: _success),
              const SizedBox(height: 16),
            ],
            _UpdateButton(
              saving: _saving,
              label: 'Change Password',
              onPressed: _changePassword,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordField({
    required String label,
    required TextEditingController controller,
    required String hint,
    required bool obscure,
    required VoidCallback onToggle,
    String? Function(String?)? validator,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final labelColor = isDark ? const Color(0xFFCBD5E1) : _kNavy;
    final hintColor = isDark ? const Color(0xFF94A3B8) : _kLightGray;
    final fillColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final fieldBorder = isDark ? const Color(0xFF334155) : _kBorder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          style: TextStyle(fontSize: 14, color: labelColor),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(fontSize: 14, color: hintColor),
            filled: true,
            fillColor: fillColor,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            suffixIcon: IconButton(
              icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18,
                  color: hintColor),
              onPressed: onToggle,
              splashRadius: 16,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: fieldBorder, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _kPrimaryBlue, width: 1.5),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: Color(0xFFEA4335)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide:
                  const BorderSide(color: Color(0xFFEA4335), width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SYSTEM TAB
// ═══════════════════════════════════════════════════════
class _SystemTab extends StatefulWidget {
  const _SystemTab();

  @override
  State<_SystemTab> createState() => _SystemTabState();
}

class _SystemTabState extends State<_SystemTab> {
  bool _checking = false;
  String _apiStatus = '—';
  String _dbStatus = '—';
  bool _apiOk = false;
  bool _dbOk = false;

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _apiStatus = 'Checking…';
      _dbStatus = 'Checking…';
    });
    try {
      final api = await ApiService.testConnection();
      setState(() {
        _apiStatus = api;
        _apiOk = true;
      });
    } catch (e) {
      setState(() {
        _apiStatus = 'Unreachable';
        _apiOk = false;
      });
    }
    try {
      final db = await ApiService.getDbStatus();
      setState(() {
        _dbOk = (db['status'] ?? '').toString().toLowerCase() == 'connected';
        _dbStatus = db['status']?.toString() ?? 'Unknown';
        _checking = false;
      });
    } catch (e) {
      setState(() {
        _dbStatus = 'Error';
        _dbOk = false;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textSecondary = isDark ? const Color(0xFF94A3B8) : _kGray;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Check SGCO system backend and database connectivity',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 24),
          _StatusRow(
              label: 'SGCO system backend', status: _apiStatus, ok: _apiOk),
          const SizedBox(height: 12),
          _StatusRow(label: 'Database', status: _dbStatus, ok: _dbOk),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh, size: 16),
            label: Text(_checking ? 'Checking…' : 'Check Connection'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kPrimaryBlue,
              side: const BorderSide(color: _kPrimaryBlue),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String status;
  final bool ok;

  const _StatusRow(
      {required this.label, required this.status, required this.ok});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxColor = isDark ? const Color(0xFF0F172A) : _kBg;
    final labelColor = isDark ? const Color(0xFFCBD5E1) : _kNavy;
    final Color dot = status == '—' || status == 'Checking…'
        ? Colors.grey
        : ok
            ? const Color(0xFF34A853)
            : const Color(0xFFEA4335);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: boxColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: dot),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: labelColor)),
          ),
          Text(status,
              style: TextStyle(
                  fontSize: 12, color: dot, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  ABOUT TAB
// ═══════════════════════════════════════════════════════
class _AboutTab extends StatelessWidget {
  const _AboutTab();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final boxColor = isDark ? const Color(0xFF0F172A) : _kBg;
    final textPrimary = isDark ? const Color(0xFFE5E7EB) : _kNavy;
    final textSecondary = isDark ? const Color(0xFF94A3B8) : _kGray;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoRow(
              'Application', AppConfig.appName, textPrimary, textSecondary),
          _infoRow('Version', AppConfig.appVersion, textPrimary, textSecondary),
          _infoRow('Platform', 'Flutter Desktop (Windows)', textPrimary,
              textSecondary),
          _infoRow('Backend', 'Node.js + Express', textPrimary, textSecondary),
          _infoRow('Database', 'PostgreSQL', textPrimary, textSecondary),
          _infoRow('Developer', 'Internal Team', textPrimary, textSecondary),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: boxColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '© 2026 ${AppConfig.appName}. All rights reserved.\n'
              'This software is intended for internal use only.',
              style: TextStyle(fontSize: 12, color: textSecondary, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(
      String label, String value, Color textPrimary, Color textSecondary) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13,
                    color: textSecondary,
                    fontWeight: FontWeight.w400)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13,
                    color: textPrimary,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SHARED WIDGETS
// ═══════════════════════════════════════════════════════
class _UpdateButton extends StatelessWidget {
  final bool saving;
  final String label;
  final VoidCallback? onPressed;

  const _UpdateButton({
    required this.saving,
    this.label = 'Update',
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ElevatedButton(
        onPressed: saving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kPrimaryBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
      ),
    );
  }
}

class _MessageBanner extends StatelessWidget {
  final String message;
  final bool success;

  const _MessageBanner({required this.message, required this.success});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = success ? const Color(0xFF34A853) : const Color(0xFFEA4335);
    final lightBg = success ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6);

    final surface = Theme.of(context).colorScheme.surface;
    final bg = isDark
        ? Color.alphaBlend(base.withValues(alpha: 0.18), surface)
        : lightBg;
    final fg = isDark ? base.withValues(alpha: 0.95) : base;
    final borderColor =
        isDark ? base.withValues(alpha: 0.35) : Colors.transparent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(success ? Icons.check_circle_outline : Icons.error_outline,
              size: 16, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12, color: fg, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}
