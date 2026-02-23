import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../services/api_service.dart';
import '../models/user.dart';

// ── Colour constants (clean modern palette) ──
const Color _kContentBg = Color(0xFFFFFFFF); // white base
const Color _kNavy = Color(0xFF202124); // near-black text

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
  String _roleFilter = 'All Users';
  String _statusFilter = 'All Status';
  String _sortMode = 'Sort by Name';
  final TextEditingController _searchController = TextEditingController();

  // Pagination state
  int _currentPage = 1;
  int _itemsPerPage = 20;
  final List<int> _itemsPerPageOptions = [10, 20, 50];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final users = await ApiService.getUsers();
      final departments = await ApiService.getDepartments();

      setState(() {
        _users = users;
        _departments = departments;
        _isLoading = false;
      });
      _applyFilters();
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
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
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                              color: Colors.blue[50],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.person_add,
                              color: Colors.blue[700],
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Create New User',
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Add a new user to your organization',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey[600],
                                  ),
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
                                const Text(
                                  'First Name',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: firstNameController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter first name',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: _kNavy, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
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
                                const Text(
                                  'Last Name',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: lastNameController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter last name',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: _kNavy, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
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
                                const Text(
                                  'Middle Initial',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: middleInitialController,
                                  decoration: InputDecoration(
                                    hintText: 'Optional',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: _kNavy, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.grey[50],
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
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
                                const Text(
                                  'Username',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: usernameController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter username',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: _kNavy, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return 'Required';
                                    if (value.length < 3)
                                      return 'Min 3 characters';
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
                                const Text(
                                  'Email',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: emailController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter email address',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: _kNavy, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return 'Required';
                                    if (!value.contains('@'))
                                      return 'Invalid email';
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
                                const Text(
                                  'Password',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: _kNavy,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  controller: passwordController,
                                  decoration: InputDecoration(
                                    hintText: 'Enter password',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide:
                                          BorderSide(color: Colors.grey[300]!),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                      borderSide: const BorderSide(
                                          color: _kNavy, width: 2),
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 14,
                                    ),
                                  ),
                                  obscureText: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty)
                                      return 'Required';
                                    if (value.length < 6)
                                      return 'Min 6 characters';
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
                      const Text(
                        'Role',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _kNavy,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
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
                          const Text(
                            'Department',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: _kNavy,
                            ),
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
                                        size: 16, color: Colors.blue[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'New',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue[700],
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
                                        size: 16, color: Colors.blue[700]),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Manage',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.blue[700],
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
                          border: Border.all(color: Colors.grey[300]!),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.white,
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: selectedDepartment,
                            hint: Text(
                              'None',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            isExpanded: true,
                            icon: Icon(Icons.keyboard_arrow_down,
                                color: Colors.grey[600]),
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
                                side: BorderSide(color: Colors.grey[300]!),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _kNavy,
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
                                      username: usernameController.text.trim(),
                                      email: emailController.text.trim(),
                                      password: passwordController.text,
                                      fullName: fullName.trim(),
                                      role: selectedRole,
                                      departmentId: selectedDepartment,
                                    );

                                    if (context.mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content:
                                              Text('User created successfully'),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                      _loadData();
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content:
                                              Text('Failed to create user: $e'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[600],
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
      ),
    );
  }

  Widget _buildRoleButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[600] : Colors.white,
            border: Border.all(
              color: isSelected ? Colors.blue[600]! : Colors.grey[300]!,
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
                color: isSelected ? Colors.white : _kNavy,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.business, color: Colors.blue[700], size: 20),
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Department created successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to create department: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    color: Colors.blue[50],
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
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.business,
                          color: Colors.blue[700],
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
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Department deleted successfully'),
                                                backgroundColor: Colors.green,
                                              ),
                                            );
                                          }
                                        } catch (e) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Failed to delete department: $e'),
                                                backgroundColor: Colors.red,
                                              ),
                                            );
                                          }
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
                          color: Colors.blue[700],
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
                    value: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
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
                    value: selectedDepartment,
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('User updated successfully'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadData();
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update user: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('User deactivated'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to deactivate user: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('User "${user.username}" permanently deleted'),
              backgroundColor: Colors.green,
            ),
          );
          _loadData();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to delete user: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _reactivateUser(User user) async {
    try {
      await ApiService.reactivateUser(user.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User reactivated'),
            backgroundColor: Colors.green,
          ),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reactivate user: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
      backgroundColor: _kContentBg,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildErrorState()
              : Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Title ──
                      const Text(
                        'User Management',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _kNavy,
                          letterSpacing: 0.2,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Stat cards row ──
                      _buildStatCards(),
                      const SizedBox(height: 20),

                      // ── Toolbar row ──
                      _buildToolbar(),
                      const SizedBox(height: 12),

                      // ── Table header ──
                      _buildTableHeader(),

                      // ── User rows with pagination ──
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: _buildUserList()),
                            const SizedBox(height: 16),
                            _buildPaginationControls(),
                          ],
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
          const Icon(Icons.error, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text('Error: $_error'),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _loadData, child: const Text('Retry')),
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
        _statCard('$total', 'Total Users'),
        const SizedBox(width: 16),
        _statCard('$active', 'Total Users'),
        const SizedBox(width: 16),
        _statCard('$suspended', 'Suspended'),
        const SizedBox(width: 16),
        _statCard('$newThisMonth', 'New This Month'),
      ],
    );
  }

  Widget _statCard(String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: _kNavy,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          // Label
          const Text(
            'User Accounts',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _kNavy,
            ),
          ),
          const SizedBox(width: 16),

          // Search field
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search users...',
                  hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  isDense: true,
                ),
                onChanged: (v) {
                  _searchQuery = v;
                  _applyFilters();
                },
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Role filter
          _toolbarButton(
            _roleFilter,
            items: ['All Users', 'Editor', 'Viewer'],
            onSelected: (v) {
              setState(() => _roleFilter = v);
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),

          // Status filter
          _toolbarButton(
            _statusFilter,
            items: ['All Status', 'Active', 'Suspended'],
            onSelected: (v) {
              setState(() => _statusFilter = v);
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),

          // Sort button
          _toolbarButton(
            _sortMode,
            items: ['Sort by Name', 'Sort by Role', 'Sort by Date'],
            onSelected: (v) {
              setState(() => _sortMode = v);
              _applyFilters();
            },
          ),
          const SizedBox(width: 8),

          // Add User button
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: _showCreateUserDialog,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Add User',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _kNavy,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolbarButton(
    String label, {
    required List<String> items,
    required ValueChanged<String> onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      itemBuilder: (_) => items
          .map((e) => PopupMenuItem(
              value: e, child: Text(e, style: const TextStyle(fontSize: 13))))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500, color: _kNavy)),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.grey[600]),
          ],
        ),
      ),
    );
  }

  // ════════════════════════════════════════════
  //  Table header
  // ════════════════════════════════════════════
  Widget _buildTableHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Row(
        children: [
          SizedBox(width: 50, child: Text('#', style: _headerStyle())),
          Expanded(flex: 3, child: Text('User', style: _headerStyle())),
          Expanded(flex: 3, child: Text('Email', style: _headerStyle())),
          Expanded(flex: 2, child: Text('Role', style: _headerStyle())),
          Expanded(flex: 2, child: Text('Status', style: _headerStyle())),
          const SizedBox(width: 48), // action column
        ],
      ),
    );
  }

  TextStyle _headerStyle() {
    return TextStyle(
        fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[600]);
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
            Icon(Icons.people_outline, size: 56, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('No users found',
                style: TextStyle(fontSize: 15, color: Colors.grey[500])),
          ],
        ),
      );
    }

    // Calculate pagination
    final totalItems = _filteredUsers.length;
    final totalPages = (totalItems / _itemsPerPage).ceil();

    // Ensure current page is valid
    if (_currentPage > totalPages && totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _currentPage = totalPages);
      });
    }

    final startIndex = (_currentPage - 1) * _itemsPerPage;
    final endIndex = (startIndex + _itemsPerPage).clamp(0, totalItems);
    final paginatedUsers = _filteredUsers.sublist(startIndex, endIndex);

    return ListView.separated(
      itemCount: paginatedUsers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final user = paginatedUsers[index];
        final rowNum = startIndex + index + 1; // Global row number
        return _buildUserRow(rowNum, user);
      },
    );
  }

  Widget _buildUserRow(int rowNum, User user) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(
              '$rowNum',
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500, color: _kNavy),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user.fullName ?? user.username,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: user.isActive ? _kNavy : Colors.grey,
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              user.email,
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: _getRoleColor(user.role).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: _getRoleColor(user.role).withAlpha(100)),
                  ),
                  child: Text(
                    user.role.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _getRoleColor(user.role),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: user.isActive
                        ? Colors.green.withAlpha(30)
                        : Colors.red.withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: user.isActive
                          ? Colors.green.withAlpha(100)
                          : Colors.red.withAlpha(100),
                    ),
                  ),
                  child: Text(
                    user.isActive ? 'ACTIVE' : 'SUSPENDED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color:
                          user.isActive ? Colors.green[700] : Colors.red[700],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 48,
            child: PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 18, color: Colors.grey[600]),
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
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('Edit'),
                    ],
                  ),
                ),
                if (user.isActive)
                  const PopupMenuItem(
                    value: 'deactivate',
                    child: Row(
                      children: [
                        Icon(Icons.block, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Deactivate', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  )
                else
                  const PopupMenuItem(
                    value: 'reactivate',
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Reactivate',
                            style: TextStyle(color: Colors.green)),
                      ],
                    ),
                  ),
                if (user.role != 'admin')
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_forever, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('Delete', style: TextStyle(color: Colors.red)),
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
    final totalPages = (totalItems / _itemsPerPage).ceil();

    if (totalItems == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Items per page selector
          Row(
            children: [
              Text(
                'Show:',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade300),
                  borderRadius: BorderRadius.circular(8),
                  color: Colors.white,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _itemsPerPage,
                    isDense: true,
                    icon: Icon(Icons.arrow_drop_down,
                        size: 20, color: Colors.grey[600]),
                    style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                    items: _itemsPerPageOptions.map((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text('$value'),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _itemsPerPage = value;
                          _currentPage = 1;
                        });
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'users',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(width: 24),
              Text(
                'Showing ${(_currentPage - 1) * _itemsPerPage + 1}-${((_currentPage - 1) * _itemsPerPage + _itemsPerPage).clamp(0, totalItems)} of $totalItems',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),

          // Page navigation
          Row(
            children: [
              // Previous button
              IconButton(
                icon: Icon(Icons.chevron_left,
                    color: _currentPage > 1 ? _kNavy : Colors.grey[400]),
                onPressed: _currentPage > 1
                    ? () => setState(() => _currentPage--)
                    : null,
                tooltip: 'Previous page',
                splashRadius: 20,
              ),

              // Page numbers
              ..._buildPageNumbers(totalPages),

              // Next button
              IconButton(
                icon: Icon(Icons.chevron_right,
                    color:
                        _currentPage < totalPages ? _kNavy : Colors.grey[400]),
                onPressed: _currentPage < totalPages
                    ? () => setState(() => _currentPage++)
                    : null,
                tooltip: 'Next page',
                splashRadius: 20,
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildPageNumbers(int totalPages) {
    List<Widget> pageButtons = [];

    // Show up to 5 page numbers at a time
    int startPage = (_currentPage - 2).clamp(1, totalPages);
    int endPage = (startPage + 4).clamp(1, totalPages);

    // Adjust start if we're near the end
    if (endPage - startPage < 4) {
      startPage = (endPage - 4).clamp(1, totalPages);
    }

    // First page if not in range
    if (startPage > 1) {
      pageButtons.add(_buildPageButton(1));
      if (startPage > 2) {
        pageButtons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey[400])),
        ));
      }
    }

    // Page number buttons
    for (int i = startPage; i <= endPage; i++) {
      pageButtons.add(_buildPageButton(i));
    }

    // Last page if not in range
    if (endPage < totalPages) {
      if (endPage < totalPages - 1) {
        pageButtons.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text('...', style: TextStyle(color: Colors.grey[400])),
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
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? _kNavy : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive ? _kNavy : Colors.grey.shade300,
              width: 1,
            ),
          ),
          child: Text(
            '$pageNumber',
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              color: isActive ? Colors.white : Colors.grey[700],
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
        return Colors.purple;
      case 'editor':
        return Colors.orange;
      case 'viewer':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }
}
