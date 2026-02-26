import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../config/constants.dart';

// ── Colour constants (Blue & Red brand palette) ──
const Color _kAccent = AppColors.primaryBlue;
const Color _kNavyS = AppColors.darkText;
const Color _kGray = AppColors.grayText;
const Color _kBorder = AppColors.border;
const Color _kBg = AppColors.bgLight;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _section = 0; // 0=Account, 1=Security, 2=System, 3=About

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final sections = [
      _Section(Icons.person_outline, 'Account'),
      _Section(Icons.lock_outline, 'Security'),
      _Section(Icons.dns_outlined, 'System Status'),
      _Section(Icons.info_outline, 'About'),
    ];

    final pages = [
      _AccountSection(auth: auth),
      _SecuritySection(auth: auth),
      const _SystemSection(),
      const _AboutSection(),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Page title ──
            const Text(
              'Settings',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: _kNavyS,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Manage your account and system preferences',
              style: TextStyle(fontSize: 13, color: _kGray),
            ),
            const SizedBox(height: 20),

            // ── Two-column layout ──
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left nav panel
                  Container(
                    width: 200,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _kBorder),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      children: sections.asMap().entries.map((e) {
                        final selected = _section == e.key;
                        return _SectionTile(
                          section: e.value,
                          selected: selected,
                          onTap: () => setState(() => _section = e.key),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(width: 20),

                  // Right content panel
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _kBorder),
                      ),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: KeyedSubtree(
                          key: ValueKey(_section),
                          child: pages[_section],
                        ),
                      ),
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

// ── Section tile for left nav ──
class _SectionTile extends StatelessWidget {
  final _Section section;
  final bool selected;
  final VoidCallback onTap;

  const _SectionTile({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? AppColors.lightBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(section.icon,
                    size: 18, color: selected ? _kAccent : _kGray),
                const SizedBox(width: 10),
                Text(
                  section.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? _kAccent : _kNavyS,
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

class _Section {
  final IconData icon;
  final String label;
  _Section(this.icon, this.label);
}

// ═══════════════════════════════════════════════════════
//  ACCOUNT SECTION
// ═══════════════════════════════════════════════════════
class _AccountSection extends StatefulWidget {
  final AuthProvider auth;
  const _AccountSection({required this.auth});

  @override
  State<_AccountSection> createState() => _AccountSectionState();
}

class _AccountSectionState extends State<_AccountSection> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _fullNameCtrl;
  late TextEditingController _emailCtrl;
  bool _saving = false;
  String? _message;
  bool _success = false;

  @override
  void initState() {
    super.initState();
    final u = widget.auth.user;
    _fullNameCtrl = TextEditingController(text: u?.fullName ?? '');
    _emailCtrl = TextEditingController(text: u?.email ?? '');
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final u = widget.auth.user!;
      await ApiService.updateUser(
        userId: u.id,
        fullName: _fullNameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );
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
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.person_outline, 'Account',
              'Update your profile information'),
          const SizedBox(height: 24),

          // Avatar row
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.lightBlue,
                child: Icon(Icons.person, color: _kAccent, size: 32),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    u?.fullName ?? u?.username ?? '—',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: _kNavyS),
                  ),
                  const SizedBox(height: 2),
                  _RoleBadge(role: u?.role ?? ''),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Divider(color: _kBorder),
          const SizedBox(height: 20),

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('Full Name'),
                const SizedBox(height: 6),
                _textField(
                  controller: _fullNameCtrl,
                  hint: 'Enter your full name',
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                _fieldLabel('Email Address'),
                const SizedBox(height: 6),
                _textField(
                  controller: _emailCtrl,
                  hint: 'Enter your email',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Required';
                    if (!v.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                _fieldLabel('Username', muted: true),
                const SizedBox(height: 6),
                _textField(
                  controller: TextEditingController(text: u?.username ?? ''),
                  hint: '',
                  readOnly: true,
                ),
                const SizedBox(height: 24),
                if (_message != null)
                  _MessageBanner(message: _message!, success: _success),
                const SizedBox(height: 12),
                _SaveButton(saving: _saving, onPressed: _save),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SECURITY SECTION – Change Password
// ═══════════════════════════════════════════════════════
class _SecuritySection extends StatefulWidget {
  final AuthProvider auth;
  const _SecuritySection({required this.auth});

  @override
  State<_SecuritySection> createState() => _SecuritySectionState();
}

class _SecuritySectionState extends State<_SecuritySection> {
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.lock_outline, 'Security', 'Change your account password'),
          const SizedBox(height: 24),

          // Info card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF0F4FF),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBDD0F8)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: _kAccent),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Use a strong password of at least 8 characters with a mix of letters and numbers.',
                    style:
                        TextStyle(fontSize: 12, color: AppColors.primaryBlue),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _fieldLabel('New Password'),
                const SizedBox(height: 6),
                _passwordField(
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
                const SizedBox(height: 16),
                _fieldLabel('Confirm New Password'),
                const SizedBox(height: 6),
                _passwordField(
                  controller: _confirmPassCtrl,
                  hint: 'Confirm new password',
                  obscure: _obscureConfirm,
                  onToggle: () =>
                      setState(() => _obscureConfirm = !_obscureConfirm),
                  validator: (v) {
                    if (v != _newPassCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                if (_message != null)
                  _MessageBanner(message: _message!, success: _success),
                const SizedBox(height: 12),
                _SaveButton(
                    saving: _saving,
                    label: 'Change Password',
                    onPressed: _changePassword),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SYSTEM STATUS SECTION
// ═══════════════════════════════════════════════════════
class _SystemSection extends StatefulWidget {
  const _SystemSection();

  @override
  State<_SystemSection> createState() => _SystemSectionState();
}

class _SystemSectionState extends State<_SystemSection> {
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
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.dns_outlined, 'System Status',
              'Check backend and database connectivity'),
          const SizedBox(height: 24),
          _StatusRow(label: 'API Server', status: _apiStatus, ok: _apiOk),
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
              foregroundColor: _kAccent,
              side: const BorderSide(color: _kAccent),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
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
    final Color dot = status == '—' || status == 'Checking…'
        ? Colors.grey
        : ok
            ? const Color(0xFF34A853)
            : const Color(0xFFEA4335);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _kBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: dot),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: _kNavyS)),
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
//  ABOUT SECTION
// ═══════════════════════════════════════════════════════
class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
              Icons.info_outline, 'About', 'Application information'),
          const SizedBox(height: 24),
          _infoRow('Application', 'Sales Management System'),
          _infoRow('Version', '1.0.0'),
          _infoRow('Platform', 'Flutter Desktop (Windows)'),
          _infoRow('Backend', 'Node.js + Express'),
          _infoRow('Database', 'PostgreSQL'),
          _infoRow('Developer', 'Internal Team'),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _kBorder),
            ),
            child: const Text(
              '© 2026 Sales Management System. All rights reserved.\n'
              'This software is intended for internal use only.',
              style: TextStyle(fontSize: 12, color: _kGray, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: _kGray, fontWeight: FontWeight.w400)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, color: _kNavyS, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════
//  SHARED HELPERS
// ═══════════════════════════════════════════════════════
Widget _sectionHeader(IconData icon, String title, String subtitle) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: _kAccent),
          ),
          const SizedBox(width: 12),
          Text(title,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w700, color: _kNavyS)),
        ],
      ),
      const SizedBox(height: 4),
      Padding(
        padding: const EdgeInsets.only(left: 46),
        child:
            Text(subtitle, style: const TextStyle(fontSize: 12, color: _kGray)),
      ),
    ],
  );
}

Widget _fieldLabel(String text, {bool muted = false}) {
  return Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: muted ? _kGray : _kNavyS,
    ),
  );
}

Widget _textField({
  required TextEditingController controller,
  required String hint,
  bool readOnly = false,
  TextInputType? keyboardType,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    readOnly: readOnly,
    keyboardType: keyboardType,
    validator: validator,
    style: const TextStyle(fontSize: 13, color: _kNavyS),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBDC1C6)),
      filled: true,
      fillColor: readOnly ? _kBg : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEA4335)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEA4335), width: 1.5),
      ),
      isDense: true,
    ),
  );
}

Widget _passwordField({
  required TextEditingController controller,
  required String hint,
  required bool obscure,
  required VoidCallback onToggle,
  String? Function(String?)? validator,
}) {
  return TextFormField(
    controller: controller,
    obscureText: obscure,
    validator: validator,
    style: const TextStyle(fontSize: 13, color: _kNavyS),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13, color: Color(0xFFBDC1C6)),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      suffixIcon: IconButton(
        icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
            color: _kGray),
        onPressed: onToggle,
        splashRadius: 16,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kAccent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEA4335)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFEA4335), width: 1.5),
      ),
      isDense: true,
    ),
  );
}

class _SaveButton extends StatelessWidget {
  final bool saving;
  final String label;
  final VoidCallback? onPressed;

  const _SaveButton({
    required this.saving,
    this.label = 'Save Changes',
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 38,
      child: ElevatedButton(
        onPressed: saving ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: _kAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          disabledBackgroundColor: const Color(0xFFBDC1C6),
        ),
        child: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : Text(label,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
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
    final color = success ? const Color(0xFF34A853) : const Color(0xFFEA4335);
    final bg = success ? const Color(0xFFE6F4EA) : const Color(0xFFFCE8E6);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(success ? Icons.check_circle_outline : Icons.error_outline,
              size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(
                    fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final color = switch (role.toLowerCase()) {
      'admin' => AppColors.primaryBlue,
      'editor' => AppColors.primaryRed,
      'manager' => const Color(0xFF9334E6),
      _ => AppColors.grayText,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        role.toUpperCase(),
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}
