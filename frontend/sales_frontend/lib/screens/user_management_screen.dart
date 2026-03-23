import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../config/constants.dart';

// ── HireGround-style colour palette ──
const Color _kBlue = Color(0xFF4285F4);
const Color _kNavy = Color(0xFF1F2937);
const Color _kGray = Color(0xFF6B7280);
const Color _kBorder = Color(0xFFE5E7EB);
const Color _kBg = Color(0xFFF9FAFB);
const Color _kGreen = Color(0xFF22C55E);
const Color _kOrange = Color(0xFFF59E0B);
const Color _kRed = Color(0xFFEF4444);

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<User> _users = [];
  List<User> _filteredUsers = [];
  List<Department> _departments = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String _roleFilter = 'All Roles';
  String _statusFilter = 'All Status';
  final String _sortMode = 'Sort by Name';
  final TextEditingController _searchController = TextEditingController();

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final List<int> _itemsPerPageOptions = [10, 20, 50];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor => _isDark ? const Color(0xFF0B1220) : _kBg;
  Color get _surfaceColor => _isDark ? const Color(0xFF111827) : Colors.white;
  Color get _surfaceAltColor => _isDark ? const Color(0xFF0F172A) : _kBg;
  Color get _borderColor => _isDark ? const Color(0xFF334155) : _kBorder;
  Color get _textPrimary => _isDark ? const Color(0xFFE5E7EB) : _kNavy;
  Color get _textSecondary => _isDark ? const Color(0xFF94A3B8) : _kGray;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _safeSetState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await ApiService.getUsers();
      if (!mounted) return;
      final departments = await ApiService.getDepartments();
      if (!mounted) return;

      _safeSetState(() {
        _users = users;
        _departments = departments;
        _isLoading = false;
      });

      if (!mounted) return;
      _applyFilters();
    } catch (e) {
      _safeSetState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  String _humanizeField(String field) {
    switch (field) {
      case 'full_name':
        return 'Full name';
      case 'department_id':
        return 'Department';
      case 'email':
        return 'Email';
      case 'username':
        return 'Username';
      case 'password':
        return 'Password';
      case 'role':
        return 'Role';
      default:
        if (field.isEmpty) return 'Field';
        return field
            .replaceAll('_', ' ')
            .split(' ')
            .where((p) => p.isNotEmpty)
            .map((p) => p[0].toUpperCase() + p.substring(1))
            .join(' ');
    }
  }

  String _formatUserManagementError(Object error) {
    if (error is ApiException) {
      if (error.code == 'VALIDATION_ERROR' &&
          error.details != null &&
          error.details!.isNotEmpty) {
        final lines = <String>[];
        for (final d in error.details!) {
          final field = (d['path'] ?? d['param'] ?? '').toString();
          final msg = (d['msg'] ?? d['message'] ?? 'Invalid value').toString();

          if (field.trim().isEmpty) {
            lines.add('• $msg');
          } else {
            lines.add('• ${_humanizeField(field)}: $msg');
          }
        }
        return lines.join('\n');
      }

      return error.message;
    }

    return error.toString();
  }

  Future<void> _showErrorModal({
    required String title,
    required Object error,
  }) async {
    if (!mounted) return;
    final message = _formatUserManagementError(error);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: SelectableText(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _kNavy,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showMessageModal({
    required String title,
    required String message,
  }) async {
    if (!mounted) return;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Container(
          width: 560,
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: _kNavy,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: SelectableText(
                    message,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      color: Colors.grey[800],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _kNavy,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showCreateUserDialog() async {
    final formKey = GlobalKey<FormState>();
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final middleInitialController = TextEditingController();
    final usernameController = TextEditingController();
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    String selectedRole = 'viewer';
    int? selectedDepartment;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final cs = theme.colorScheme;

        final borderColor = cs.outline.withValues(alpha: isDark ? 0.65 : 0.45);
        final fieldFill = cs.surfaceContainerHighest;
        final hintColor = cs.onSurfaceVariant.withValues(alpha: 0.75);
        final linkColor = isDark ? cs.primaryContainer : cs.primary;

        final labelStyle = TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        );

        final subLabelStyle = TextStyle(
          fontSize: 14,
          color: cs.onSurfaceVariant,
        );

        InputDecoration deco({required String hint}) => InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(color: hintColor),
              filled: true,
              fillColor: fieldFill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: cs.primary, width: 2),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
            );

        final ShapeBorder dialogShape = theme.dialogTheme.shape ??
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor),
            );

        return Dialog(
          backgroundColor: theme.dialogTheme.backgroundColor,
          shape: dialogShape,
          child: Container(
            width: 640,
            constraints: const BoxConstraints(maxWidth: 640),
            child: StatefulBuilder(
              builder: (context, setDialogState) => SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: cs.primary
                                    .withValues(alpha: isDark ? 0.20 : 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.person_add,
                                color: cs.primary,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Create New User',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Add a new user to your organization',
                                    style: subLabelStyle,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 32),

                        // Name Fields (Two columns)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'First Name',
                                    style: labelStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: firstNameController,
                                    decoration: deco(hint: 'Enter first name'),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Last Name',
                                    style: labelStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: lastNameController,
                                    decoration: deco(hint: 'Enter last name'),
                                    validator: (value) =>
                                        value == null || value.isEmpty
                                            ? 'Required'
                                            : null,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Middle Initial and Username
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Middle Initial',
                                    style: labelStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: middleInitialController,
                                    decoration: deco(hint: 'Optional'),
                                    maxLength: 2,
                                    buildCounter: (context,
                                            {required currentLength,
                                            required isFocused,
                                            maxLength}) =>
                                        null,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Username',
                                    style: labelStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: usernameController,
                                    decoration: deco(hint: 'Enter username'),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Required';
                                      }
                                      if (value.length < 3) {
                                        return 'Min 3 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // Email and Password
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Email',
                                    style: labelStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: emailController,
                                    decoration:
                                        deco(hint: 'Enter email address'),
                                    keyboardType: TextInputType.emailAddress,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Required';
                                      }
                                      if (!value.contains('@')) {
                                        return 'Invalid email';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Password',
                                    style: labelStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: passwordController,
                                    decoration: deco(hint: 'Enter password'),
                                    obscureText: true,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Required';
                                      }
                                      if (value.length < 6) {
                                        return 'Min 6 characters';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Role Selection (Segmented Buttons)
                        Text(
                          'Role',
                          style: labelStyle,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _buildRoleButton(
                              label: 'Admin',
                              isSelected: selectedRole == 'admin',
                              onTap: () =>
                                  setDialogState(() => selectedRole = 'admin'),
                            ),
                            const SizedBox(width: 12),
                            _buildRoleButton(
                              label: 'Editor',
                              isSelected: selectedRole == 'editor',
                              onTap: () =>
                                  setDialogState(() => selectedRole = 'editor'),
                            ),
                            const SizedBox(width: 12),
                            _buildRoleButton(
                              label: 'Viewer',
                              isSelected: selectedRole == 'viewer',
                              onTap: () =>
                                  setDialogState(() => selectedRole = 'viewer'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        // Department Section
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Department',
                              style: labelStyle,
                            ),
                            Row(
                              children: [
                                InkWell(
                                  onTap: () async {
                                    final result =
                                        await _showAddDepartmentDialog();
                                    if (result != null) {
                                      setDialogState(() {
                                        // Department was added, refresh the list
                                      });
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      Icon(Icons.add,
                                          size: 16, color: linkColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'New',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: linkColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                InkWell(
                                  onTap: () async {
                                    final needsUpdate =
                                        await _showManageDepartmentsDialog();
                                    if (needsUpdate == true) {
                                      setDialogState(() {
                                        // Check if selected department was deleted
                                        if (selectedDepartment != null &&
                                            !_departments.any((d) =>
                                                d.id == selectedDepartment)) {
                                          selectedDepartment = null;
                                        }
                                      });
                                    }
                                  },
                                  child: Row(
                                    children: [
                                      Icon(Icons.settings,
                                          size: 16, color: linkColor),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Manage',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: linkColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            border: Border.all(color: borderColor),
                            borderRadius: BorderRadius.circular(8),
                            color: fieldFill,
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int?>(
                              value: selectedDepartment,
                              hint: Text(
                                'None',
                                style: TextStyle(color: hintColor),
                              ),
                              isExpanded: true,
                              icon: Icon(Icons.keyboard_arrow_down,
                                  color: cs.onSurfaceVariant),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text('None'),
                                ),
                                ..._departments.map((dept) => DropdownMenuItem(
                                      value: dept.id,
                                      child: Text(dept.name),
                                    )),
                              ],
                              onChanged: (value) {
                                setDialogState(() {
                                  selectedDepartment = value;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // Actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Cancel Button
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(context),
                                style: OutlinedButton.styleFrom(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  side: BorderSide(color: borderColor),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: Text(
                                  'Cancel',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: cs.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            // Create Button
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () async {
                                  if (formKey.currentState!.validate()) {
                                    final fullName =
                                        '${firstNameController.text.trim()} '
                                        '${middleInitialController.text.trim().isNotEmpty ? "${middleInitialController.text.trim()}. " : ""}'
                                        '${lastNameController.text.trim()}';

                                    try {
                                      await ApiService.createUser(
                                        username:
                                            usernameController.text.trim(),
                                        email: emailController.text.trim(),
                                        password: passwordController.text,
                                        fullName: fullName.trim(),
                                        role: selectedRole,
                                        departmentId: selectedDepartment,
                                      );

                                      if (context.mounted) {
                                        Navigator.pop(context);
                                        _loadData();
                                        await _showMessageModal(
                                          title: 'User created',
                                          message: 'User created successfully.',
                                        );
                                      }
                                    } catch (e) {
                                      await _showErrorModal(
                                        title: 'Create user failed',
                                        error: e,
                                      );
                                    }
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text(
                                  'Create User',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;
    final borderColor = cs.outline.withValues(alpha: isDark ? 0.65 : 0.45);
    final unselectedFill = cs.surfaceContainerHighest;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryBlue : unselectedFill,
            border: Border.all(
              color: isSelected ? AppColors.primaryBlue : borderColor,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : cs.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Add Department Dialog
  // ═══════════════════════════════════════════
  Future<bool?> _showAddDepartmentDialog() async {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.lightBlue,
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  Icon(Icons.business, color: AppColors.primaryBlue, size: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Create New Department',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Department Name',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _kNavy,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    hintText: 'Enter department name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Department name is required';
                    }
                    // Check for duplicates
                    if (_departments.any((d) =>
                        d.name.toLowerCase() == value.trim().toLowerCase())) {
                      return 'Department already exists';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                const Text(
                  'Description (Optional)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _kNavy,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: descriptionController,
                  decoration: InputDecoration(
                    hintText: 'Enter description',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  final newDept = await ApiService.createDepartment(
                    name: nameController.text.trim(),
                    description: descriptionController.text.trim(),
                  );

                  setState(() {
                    _departments.add(newDept);
                  });

                  if (context.mounted) {
                    Navigator.pop(context, true);
                    await _showMessageModal(
                      title: 'Department created',
                      message: 'Department created successfully.',
                    );
                  }
                } catch (e) {
                  await _showErrorModal(
                    title: 'Create department failed',
                    error: e,
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save Department'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════
  //  Manage Departments Dialog
  // ═══════════════════════════════════════════
  Future<bool?> _showManageDepartmentsDialog() async {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.border),
        ),
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
          child: StatefulBuilder(
            builder: (context, setDialogState) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.lightBlue,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.lightBlue,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.business,
                          color: AppColors.primaryBlue,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Manage Departments',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _kNavy,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_departments.length} departments',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Department List
                Flexible(
                  child: _departments.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(48),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.business_outlined,
                                size: 64,
                                color: Colors.grey[300],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No departments yet',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[500],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Create your first department',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[400],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(24),
                          shrinkWrap: true,
                          itemCount: _departments.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            final dept = _departments[index];
                            return Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey[200]!),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          dept.name,
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: _kNavy,
                                          ),
                                        ),
                                        if (dept.description != null &&
                                            dept.description!.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            dept.description!,
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline),
                                    color: Colors.red[400],
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                          ),
                                          title:
                                              const Text('Delete Department'),
                                          content: Text(
                                            'Are you sure you want to delete "${dept.name}"?\n\nThis action cannot be undone.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            ElevatedButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.red,
                                                foregroundColor: Colors.white,
                                              ),
                                              child: const Text('Delete'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirm == true) {
                                        try {
                                          await ApiService.deleteDepartment(
                                              dept.id);

                                          setState(() {
                                            _departments.removeWhere(
                                                (d) => d.id == dept.id);
                                          });

                                          setDialogState(() {});

                                          if (context.mounted) {
                                            await _showMessageModal(
                                              title: 'Department deleted',
                                              message:
                                                  'Department deleted successfully.',
                                            );
                                          }
                                        } catch (e) {
                                          await _showErrorModal(
                                            title: 'Delete department failed',
                                            error: e,
                                          );
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),

                // Close Button
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text(
                        'Close',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryBlue,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showEditUserDialog(User user) async {
    final formKey = GlobalKey<FormState>();
    final usernameController = TextEditingController(text: user.username);
    final emailController = TextEditingController(text: user.email);
    final fullNameController = TextEditingController(text: user.fullName);
    final passwordController = TextEditingController();
    String selectedRole = user.role == 'user' ? 'viewer' : user.role;
    int? selectedDepartment = user.departmentId;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit User: ${user.username}'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      if (value.length < 3) return 'Min 3 characters';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Required';
                      if (!value.contains('@')) return 'Invalid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: passwordController,
                    decoration: const InputDecoration(
                      labelText: 'New Password (leave empty to keep current)',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value != null &&
                          value.isNotEmpty &&
                          value.length < 6) {
                        return 'Min 6 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'viewer', child: Text('Viewer')),
                      DropdownMenuItem(value: 'editor', child: Text('Editor')),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedRole = value!;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: selectedDepartment,
                    decoration: const InputDecoration(
                      labelText: 'Department',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('None')),
                      ..._departments.map((dept) => DropdownMenuItem(
                            value: dept.id,
                            child: Text(dept.name),
                          )),
                    ],
                    onChanged: (value) {
                      setDialogState(() {
                        selectedDepartment = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState!.validate()) {
                try {
                  await ApiService.updateUser(
                    userId: user.id,
                    username: usernameController.text,
                    email: emailController.text,
                    fullName: fullNameController.text,
                    password: passwordController.text.isEmpty
                        ? null
                        : passwordController.text,
                    role: selectedRole,
                    departmentId: selectedDepartment,
                  );

                  if (context.mounted) {
                    Navigator.pop(context);
                    _loadData();
                    await _showMessageModal(
                      title: 'User updated',
                      message: 'User updated successfully.',
                    );
                  }
                } catch (e) {
                  await _showErrorModal(
                    title: 'Update user failed',
                    error: e,
                  );
                }
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeactivate(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Deactivate User'),
        content: Text(
            'Are you sure you want to deactivate "${user.username}"? They will no longer be able to log in.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deactivateUser(user.id);
        if (mounted) {
          _loadData();
          await _showMessageModal(
            title: 'User deactivated',
            message: 'User deactivated successfully.',
          );
        }
      } catch (e) {
        await _showErrorModal(title: 'Deactivate user failed', error: e);
      }
    }
  }

  Future<void> _confirmDeleteUser(User user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete User Permanently'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Are you sure you want to permanently delete "${user.username}"?'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This action cannot be undone. All data associated with this user will be permanently removed.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await ApiService.deleteUserPermanently(user.id);
        if (mounted) {
          _loadData();
          await _showMessageModal(
            title: 'User deleted',
            message: 'User "${user.username}" permanently deleted.',
          );
        }
      } catch (e) {
        await _showErrorModal(title: 'Delete user failed', error: e);
      }
    }
  }

  Future<void> _reactivateUser(User user) async {
    try {
      await ApiService.reactivateUser(user.id);
      if (mounted) {
        _loadData();
        await _showMessageModal(
          title: 'User reactivated',
          message: 'User reactivated successfully.',
        );
      }
    } catch (e) {
      await _showErrorModal(title: 'Reactivate user failed', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Check if user is admin
    if (authProvider.user?.role != 'admin') {
      return const Scaffold(
        body: Center(
          child: Text('Access Denied - Admin Only'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bgColor,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _kBlue))
          : _error != null
              ? _buildErrorState()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Stat cards row ──
                      _buildStatCards(),
                      const SizedBox(height: 24),

                      // ── Table container ──
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: _surfaceColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _borderColor),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Column(
                            children: [
                              // ── Toolbar row ──
                              _buildToolbar(),

                              // ── Table header ──
                              _buildTableHeader(),

                              // ── User rows ──
                              Expanded(child: _buildUserList()),

                              // ── Pagination ──
                              _buildPaginationControls(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ════════════════════════════════════════════
  //  Error state
  // ════════════════════════════════════════════
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kRed.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.error_outline_rounded, size: 48, color: _kRed),
          ),
          const SizedBox(height: 20),
          Text(
            'Something went wrong',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600, color: _textPrimary),
          ),
          const SizedBox(height: 8),
          Text('$_error',
              style: TextStyle(fontSize: 13, color: _textSecondary)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Stat Cards
  // ════════════════════════════════════════════
  Widget _buildStatCards() {
    final total = _users.length;
    final active = _users.where((u) => u.isActive).length;
    final suspended = _users.where((u) => !u.isActive).length;
    final now = DateTime.now();
    final newThisMonth = _users.where((u) {
      if (u.createdAt == null) return false;
      return u.createdAt!.year == now.year && u.createdAt!.month == now.month;
    }).length;

    return Row(
      children: [
        _statCard('$total', 'Total Users', Icons.people_rounded, _kBlue),
        const SizedBox(width: 16),
        _statCard(
            '$active', 'Active Users', Icons.check_circle_rounded, _kGreen),
        const SizedBox(width: 16),
        _statCard('$suspended', 'Suspended', Icons.block_rounded, _kRed),
        const SizedBox(width: 16),
        _statCard('$newThisMonth', 'New This Month', Icons.person_add_rounded,
            _kOrange),
      ],
    );
  }

  Widget _statCard(String value, String label, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 12, color: _textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Toolbar (search + filters + add)
  // ════════════════════════════════════════════
  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          // Title
          Text(
            'User Management',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
            ),
          ),
          const SizedBox(width: 20),

          // Search field - modern pill style
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: _surfaceAltColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _borderColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 13, color: _textPrimary),
                decoration: InputDecoration(
                  hintText: 'Search by name, username or email...',
                  hintStyle: TextStyle(fontSize: 13, color: _textSecondary),
                  prefixIcon: Icon(Icons.search_rounded,
                      color: _textSecondary, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: _textSecondary, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _searchQuery = '';
                            _applyFilters();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onChanged: (v) {
                  _searchQuery = v;
                  _applyFilters();
                },
              ),
            ),
          ),
          const SizedBox(width: 16),

          // Role filter - modern dropdown
          _buildModernDropdown(
            value: _roleFilter,
            allLabel: 'All Roles',
            icon: Icons.badge_rounded,
            items: ['Admin', 'Editor', 'Viewer'],
            onChanged: (v) {
              setState(() => _roleFilter = v);
              _applyFilters();
            },
          ),
          const SizedBox(width: 10),

          // Status filter
          _buildModernDropdown(
            value: _statusFilter,
            allLabel: 'All Status',
            icon: Icons.toggle_on_rounded,
            items: ['Active', 'Suspended'],
            onChanged: (v) {
              setState(() => _statusFilter = v);
              _applyFilters();
            },
          ),
          const SizedBox(width: 16),

          // Add User button - modern style
          ElevatedButton.icon(
            onPressed: _showCreateUserDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Add User'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _kBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModernDropdown({
    required String value,
    required String allLabel,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String> onChanged,
  }) {
    // NOTE: Do NOT use `null` as a menu value.
    // PopupMenuButton treats `null` as “cancel” and will not call `onSelected`,
    // which makes the "All" option impossible to re-select.
    return PopupMenuButton<String>(
      onSelected: onChanged,
      offset: const Offset(0, 45),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          value: allLabel,
          child: Row(
            children: [
              Icon(icon, size: 18, color: _kGray),
              const SizedBox(width: 10),
              Text(allLabel,
                  style: TextStyle(fontSize: 13, color: _textPrimary)),
              if (value == allLabel) ...[
                const Spacer(),
                Icon(Icons.check, size: 16, color: _kBlue),
              ],
            ],
          ),
        ),
        const PopupMenuDivider(),
        ...items.map((item) => PopupMenuItem<String>(
              value: item,
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: item == value ? _kBlue : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(item,
                      style: TextStyle(fontSize: 13, color: _textPrimary)),
                  if (item == value) ...[
                    const Spacer(),
                    Icon(Icons.check, size: 16, color: _kBlue),
                  ],
                ],
              ),
            )),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: value != allLabel
              ? _kBlue.withValues(alpha: 0.08)
              : _surfaceColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: value != allLabel
                  ? _kBlue.withValues(alpha: 0.3)
                  : _borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16, color: value != allLabel ? _kBlue : _textSecondary),
            const SizedBox(width: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: value != allLabel ? _kBlue : _textSecondary,
                fontWeight:
                    value != allLabel ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down_rounded,
                size: 18, color: value != allLabel ? _kBlue : _textSecondary),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Table header
  // ════════════════════════════════════════════
  Widget _buildTableHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: _surfaceAltColor,
        border: Border(bottom: BorderSide(color: _borderColor)),
      ),
      child: Row(
        children: [
          _headerCell('#', flex: 1),
          _headerCell('USER', flex: 3),
          _headerCell('EMAIL', flex: 3),
          _headerCell('ROLE', flex: 2),
          _headerCell('STATUS', flex: 2),
          const SizedBox(width: 60), // Actions column
        ],
      ),
    );
  }

  Widget _headerCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: _textSecondary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  User list
  // ════════════════════════════════════════════
  Widget _buildUserList() {
    if (_filteredUsers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _kBg,
                shape: BoxShape.circle,
              ),
              child:
                  Icon(Icons.people_outline_rounded, size: 48, color: _kGray),
            ),
            const SizedBox(height: 16),
            Text('No users found',
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w500, color: _kNavy)),
            const SizedBox(height: 4),
            Text('Try adjusting your filters',
                style: TextStyle(fontSize: 13, color: _kGray)),
          ],
        ),
      );
    }

    // Calculate pagination
    final totalItems = _filteredUsers.length;
    final totalPages =
        totalItems == 0 ? 1 : (totalItems / _itemsPerPage).ceil();

    // Ensure current page is valid
    if (_currentPage > totalPages && totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _currentPage = totalPages);
      });
    }

    final validPage = _currentPage.clamp(1, totalPages);
    final startIndex = ((validPage - 1) * _itemsPerPage).clamp(0, totalItems);
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
    final paginatedUsers = startIndex < totalItems
        ? _filteredUsers.sublist(startIndex, endIndex)
        : <User>[];

    return ListView.builder(
      itemCount: paginatedUsers.length,
      itemBuilder: (context, index) {
        final user = paginatedUsers[index];
        final rowNum = startIndex + index + 1;
        return _buildUserRow(rowNum, user);
      },
    );
  }

  Widget _buildUserRow(int rowNum, User user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: rowNum.isOdd
            ? _surfaceColor
            : _surfaceAltColor.withValues(alpha: 0.8),
        border: Border(
            bottom: BorderSide(color: _borderColor.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          // Row number
          Expanded(
            flex: 1,
            child: Text(
              '$rowNum',
              style: TextStyle(fontSize: 13, color: _textSecondary),
            ),
          ),
          // User info with avatar
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kBlue.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      (user.fullName ?? user.username)
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _kBlue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.fullName ?? user.username,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: user.isActive ? _textPrimary : _textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@${user.username}',
                        style: TextStyle(fontSize: 11, color: _textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Email
          Expanded(
            flex: 3,
            child: Text(
              user.email,
              style: TextStyle(fontSize: 13, color: _textSecondary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Role badge
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getRoleColor(user.role).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    user.role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _getRoleColor(user.role),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Status badge
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: user.isActive
                        ? _kGreen.withValues(alpha: 0.1)
                        : _kRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: user.isActive ? _kGreen : _kRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        user.isActive ? 'Active' : 'Suspended',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: user.isActive ? _kGreen : _kRed,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Actions
          SizedBox(
            width: 60,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_horiz_rounded, size: 20, color: _kGray),
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                switch (value) {
                  case 'edit':
                    _showEditUserDialog(user);
                    break;
                  case 'deactivate':
                    _confirmDeactivate(user);
                    break;
                  case 'reactivate':
                    _reactivateUser(user);
                    break;
                  case 'delete':
                    _confirmDeleteUser(user);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_rounded, size: 18, color: _kBlue),
                      const SizedBox(width: 10),
                      Text('Edit User',
                          style: TextStyle(fontSize: 13, color: _kNavy)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                if (user.isActive)
                  PopupMenuItem(
                    value: 'deactivate',
                    child: Row(
                      children: [
                        Icon(Icons.block_rounded, size: 18, color: _kOrange),
                        const SizedBox(width: 10),
                        Text('Suspend',
                            style: TextStyle(fontSize: 13, color: _kOrange)),
                      ],
                    ),
                  )
                else
                  PopupMenuItem(
                    value: 'reactivate',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 18, color: _kGreen),
                        const SizedBox(width: 10),
                        Text('Reactivate',
                            style: TextStyle(fontSize: 13, color: _kGreen)),
                      ],
                    ),
                  ),
                if (user.role != 'admin')
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_rounded, size: 18, color: _kRed),
                        const SizedBox(width: 10),
                        Text('Delete',
                            style: TextStyle(fontSize: 13, color: _kRed)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Pagination Controls
  // ════════════════════════════════════════════
  Widget _buildPaginationControls() {
    final totalItems = _filteredUsers.length;
    final totalPages =
        totalItems == 0 ? 1 : (totalItems / _itemsPerPage).ceil();

    if (totalItems == 0) {
      return const SizedBox.shrink();
    }

    final validPage = _currentPage.clamp(1, totalPages);
    final startIdx = ((validPage - 1) * _itemsPerPage).clamp(0, totalItems);
    final endIdx = (startIdx + _itemsPerPage).clamp(0, totalItems);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items per page and count
          Row(
            children: [
              Text('Rows per page',
                  style: TextStyle(fontSize: 13, color: _textSecondary)),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _itemsPerPage,
                    isDense: true,
                    underline: null,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: _textSecondary),
                    dropdownColor: _surfaceColor,
                    style: TextStyle(fontSize: 13, color: _textPrimary),
                    items: _itemsPerPageOptions
                        .map((v) =>
                            DropdownMenuItem(value: v, child: Text('$v')))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _itemsPerPage = v;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Text(
                'Showing ${startIdx + 1}-$endIdx of $totalItems users',
                style: TextStyle(fontSize: 13, color: _textSecondary),
              ),
            ],
          ),

          // Page navigation
          Row(
            children: [
              // First page
              _navButton(Icons.first_page_rounded, validPage > 1,
                  () => setState(() => _currentPage = 1)),
              // Previous
              _navButton(Icons.chevron_left_rounded, validPage > 1,
                  () => setState(() => _currentPage--)),
              const SizedBox(width: 8),
              // Page numbers
              ..._buildPageNumbers(totalPages),
              const SizedBox(width: 8),
              // Next
              _navButton(Icons.chevron_right_rounded, validPage < totalPages,
                  () => setState(() => _currentPage++)),
              // Last page
              _navButton(Icons.last_page_rounded, validPage < totalPages,
                  () => setState(() => _currentPage = totalPages)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _navButton(IconData icon, bool enabled, VoidCallback onTap) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(icon,
              size: 20, color: enabled ? _textPrimary : _borderColor),
        ),
      ),
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    List<Widget> pageButtons = [];
    int startPage = (_currentPage - 2).clamp(1, totalPages);
    int endPage = (startPage + 4).clamp(1, totalPages);
    if (endPage - startPage < 4) {
      startPage = (endPage - 4).clamp(1, totalPages);
    }

    if (startPage > 1) {
      pageButtons.add(_buildPageButton(1));
      if (startPage > 2) {
        pageButtons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: _textSecondary)),
        ));
      }
    }

    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(_buildPageButton(i));
    }

    if (endPage < totalPages) {
      if (endPage < totalPages - 1) {
        pageButtons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: _textSecondary)),
        ));
      }
      pageButtons.add(_buildPageButton(totalPages));
    }

    return pageButtons;
  }

  Widget _buildPageButton(int pageNumber) {
    final isActive = pageNumber == _currentPage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: InkWell(
        onTap: () => setState(() => _currentPage = pageNumber),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? _kBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$pageNumber',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
              color: isActive ? Colors.white : _textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Filtering / Sorting
  // ════════════════════════════════════════════
  void _applyFilters() {
    setState(() {
      _currentPage = 1; // Reset to first page when filters change
    });

    List<User> result = List.from(_users);

    // Search
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result.where((u) {
        return (u.fullName ?? '').toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q) ||
            u.email.toLowerCase().contains(q);
      }).toList();
    }

    // Role
    switch (_roleFilter) {
      case 'Admin':
        result = result.where((u) => u.role == 'admin').toList();
        break;
      case 'Editor':
        result = result.where((u) => u.role == 'editor').toList();
        break;
      case 'Viewer':
        result = result.where((u) => u.role == 'viewer').toList();
        break;
    }

    // Status
    switch (_statusFilter) {
      case 'Active':
        result = result.where((u) => u.isActive).toList();
        break;
      case 'Suspended':
        result = result.where((u) => !u.isActive).toList();
        break;
    }

    // Sort
    switch (_sortMode) {
      case 'Sort by Name':
        result.sort((a, b) =>
            (a.fullName ?? a.username).compareTo(b.fullName ?? b.username));
        break;
      case 'Sort by Role':
        result.sort((a, b) => a.role.compareTo(b.role));
        break;
      case 'Sort by Date':
        result.sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));
        break;
    }

    setState(() => _filteredUsers = result);
  }

  Color _getRoleColor(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return _kBlue;
      case 'editor':
        return _kOrange;
      case 'viewer':
        return _kGreen;
      default:
        return _kGray;
    }
  }
}
