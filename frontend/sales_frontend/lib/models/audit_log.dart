/// Audit log entry
class AuditLog {
  final int id;
  final int? userId;
  final String? username;
  final String action;
  final String entityType;
  final String? entityId;
  final String? entityName;
  final String? fileName;
  final int? rowNumber;
  final String? fieldName;
  final dynamic oldValue;
  final dynamic newValue;
  final String? description;
  final String? ipAddress;
  final Map<String, dynamic>? metadata;
  final DateTime? timestamp;

  // V2 collaboration fields
  final int? sheetId;
  final String? cellReference;
  final String? role;
  final String? departmentName;

  // Alias for username
  String? get userName => username;

  AuditLog({
    required this.id,
    this.userId,
    this.username,
    required this.action,
    required this.entityType,
    this.entityId,
    this.entityName,
    this.fileName,
    this.rowNumber,
    this.fieldName,
    this.oldValue,
    this.newValue,
    this.description,
    this.ipAddress,
    this.metadata,
    this.timestamp,
    this.sheetId,
    this.cellReference,
    this.role,
    this.departmentName,
  });

  factory AuditLog.fromJson(Map<String, dynamic> json) {
    return AuditLog(
      id: json['id'] ?? 0,
      userId: json['user_id'],
      username: json['username'],
      action: json['action'] ?? '',
      entityType: json['entity_type'] ?? '',
      entityId: json['entity_id']?.toString(),
      entityName: json['entity_name'],
      fileName: json['file_name'],
      rowNumber: json['row_number'],
      fieldName: json['field_name'],
      oldValue: json['old_value'],
      newValue: json['new_value'],
      description: json['description'],
      ipAddress: json['ip_address'],
      metadata: json['metadata'],
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'])
          : (json['created_at'] != null
              ? DateTime.tryParse(json['created_at'])
              : null),
      sheetId: json['sheet_id'],
      cellReference: json['cell_reference'],
      role: json['role'],
      departmentName: json['department_name'],
    );
  }

  String get actionDisplay {
    switch (action.toUpperCase()) {
      case 'CREATE':
        return 'Created';
      case 'UPDATE':
        return 'Updated';
      case 'DELETE':
        return 'Deleted';
      case 'LOGIN':
        return 'Logged in';
      case 'LOGOUT':
        return 'Logged out';
      case 'FORMULA_APPLY':
        return 'Applied formula';
      default:
        return action;
    }
  }

  String get changeDescription {
    if (fieldName != null && oldValue != null && newValue != null) {
      return '$fieldName: "$oldValue" → "$newValue"';
    } else if (fieldName != null && newValue != null) {
      return '$fieldName: "$newValue"';
    } else if (action == 'CREATE' && rowNumber != null) {
      return 'New row #$rowNumber';
    } else if (action == 'DELETE' && rowNumber != null) {
      return 'Deleted row #$rowNumber';
    }
    return '';
  }
}

/// Audit summary statistics
class AuditSummary {
  final int totalChanges;
  final int today;
  final int thisWeek;
  final Map<String, int> byAction;
  final List<UserActivityCount> byUser;
  final List<RecentActivity> recentActivity;

  AuditSummary({
    required this.totalChanges,
    required this.today,
    required this.thisWeek,
    required this.byAction,
    required this.byUser,
    required this.recentActivity,
  });

  factory AuditSummary.fromJson(Map<String, dynamic> json) {
    final summary = json['summary'] ?? json;
    return AuditSummary(
      totalChanges: summary['total_changes'] ?? 0,
      today: summary['today'] ?? 0,
      thisWeek: summary['this_week'] ?? 0,
      byAction: Map<String, int>.from(summary['by_action'] ?? {}),
      byUser: (summary['by_user'] as List?)
              ?.map((e) => UserActivityCount.fromJson(e))
              .toList() ??
          [],
      recentActivity: (summary['recent_activity'] as List?)
              ?.map((e) => RecentActivity.fromJson(e))
              .toList() ??
          [],
    );
  }
}

/// User activity count
class UserActivityCount {
  final String username;
  final int count;

  UserActivityCount({required this.username, required this.count});

  factory UserActivityCount.fromJson(Map<String, dynamic> json) {
    return UserActivityCount(
      username: json['username'] ?? 'Unknown',
      count: json['count'] ?? 0,
    );
  }
}

/// Recent activity entry
class RecentActivity {
  final String? username;
  final String action;
  final String? fileName;
  final DateTime timestamp;

  RecentActivity({
    this.username,
    required this.action,
    this.fileName,
    required this.timestamp,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      username: json['username'],
      action: json['action'] ?? '',
      fileName: json['file_name'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}
