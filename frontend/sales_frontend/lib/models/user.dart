/// User model
class User {
  final int id;
  final String username;
  final String email;
  final String? fullName;
  final String role;
  final int? departmentId;
  final String? departmentName;
  final bool isActive;
  final DateTime? lastLogin;
  final DateTime? createdAt;
  final DateTime? deactivatedAt;
  final String? createdByName;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.fullName,
    required this.role,
    this.departmentId,
    this.departmentName,
    this.isActive = true,
    this.lastLogin,
    this.createdAt,
    this.deactivatedAt,
    this.createdByName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      fullName: json['full_name'],
      role: json['role'] ?? 'user',
      departmentId: json['department_id'],
      departmentName: json['department_name'],
      isActive: json['is_active'] ?? true,
      lastLogin: json['last_login'] != null 
          ? DateTime.parse(json['last_login']) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
      deactivatedAt: json['deactivated_at'] != null
          ? DateTime.parse(json['deactivated_at'])
          : null,
      createdByName: json['created_by_name'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'full_name': fullName,
      'role': role,
      'department_id': departmentId,
      'department_name': departmentName,
      'is_active': isActive,
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isViewer => role == 'viewer';
  bool get canEdit => role != 'viewer';
}

/// Department model
class Department {
  final int id;
  final String name;
  final String? description;

  Department({
    required this.id,
    required this.name,
    this.description,
  });

  factory Department.fromJson(Map<String, dynamic> json) {
    return Department(
      id: json['id'],
      name: json['name'] ?? '',
      description: json['description'],
    );
  }
}

/// Role model
class Role {
  final int id;
  final String name;
  final String? description;

  Role({
    required this.id,
    required this.name,
    this.description,
  });

  factory Role.fromJson(Map<String, dynamic> json) {
    return Role(
      id: json['id'],
      name: json['name'] ?? '',
      description: json['description'],
    );
  }
}
