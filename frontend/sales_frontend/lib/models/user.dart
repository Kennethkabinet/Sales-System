/// User model
class User {
  final int id;
  final String username;
  final String email;
  final String? fullName;
  final String role;
  final int? departmentId;
  final String? departmentName;
  final DateTime? lastLogin;
  final DateTime? createdAt;

  User({
    required this.id,
    required this.username,
    required this.email,
    this.fullName,
    required this.role,
    this.departmentId,
    this.departmentName,
    this.lastLogin,
    this.createdAt,
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
      lastLogin: json['last_login'] != null 
          ? DateTime.parse(json['last_login']) 
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
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
