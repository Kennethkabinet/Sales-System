/// File model for Excel files
class FileModel {
  final int id;
  final String? uuid;
  final String name;
  final String? originalFilename;
  final String? fileType;
  final int? departmentId;
  final String? departmentName;
  final String? createdBy;
  final int currentVersion;
  final List<String> columns;
  final int? rowCount;
  final int activeUsers;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  // Alias for fileType
  String? get type => fileType;

  FileModel({
    required this.id,
    this.uuid,
    required this.name,
    this.originalFilename,
    this.fileType,
    this.departmentId,
    this.departmentName,
    this.createdBy,
    this.currentVersion = 1,
    this.columns = const [],
    this.rowCount,
    this.activeUsers = 0,
    this.createdAt,
    this.updatedAt,
  });

  factory FileModel.fromJson(Map<String, dynamic> json) {
    return FileModel(
      id: json['id'],
      uuid: json['uuid'],
      name: json['name'] ?? '',
      originalFilename: json['original_filename'],
      fileType: json['file_type'] ?? 'xlsx',
      departmentId: json['department_id'],
      departmentName: json['department_name'],
      createdBy: json['created_by'],
      currentVersion: json['current_version'] ?? 1,
      columns: json['columns'] != null 
          ? List<String>.from(json['columns']) 
          : [],
      rowCount: json['row_count'],
      activeUsers: json['active_users'] ?? 0,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at']) 
          : null,
      updatedAt: json['updated_at'] != null 
          ? DateTime.parse(json['updated_at']) 
          : null,
    );
  }
}

/// File data row
class FileDataRow {
  final int rowId;
  final int rowNumber;
  final Map<String, dynamic> values;
  final String? lockedBy;

  FileDataRow({
    required this.rowId,
    required this.rowNumber,
    required this.values,
    this.lockedBy,
  });

  factory FileDataRow.fromJson(Map<String, dynamic> json) {
    return FileDataRow(
      rowId: json['row_id'],
      rowNumber: json['row_number'],
      values: Map<String, dynamic>.from(json['values'] ?? {}),
      lockedBy: json['locked_by'],
    );
  }

  bool get isLocked => lockedBy != null;

  FileDataRow copyWith({
    int? rowId,
    int? rowNumber,
    Map<String, dynamic>? values,
    String? lockedBy,
  }) {
    return FileDataRow(
      rowId: rowId ?? this.rowId,
      rowNumber: rowNumber ?? this.rowNumber,
      values: values ?? Map.from(this.values),
      lockedBy: lockedBy,
    );
  }
}

/// File version
class FileVersion {
  final int version;
  final String? createdBy;
  final String? changesSummary;
  final DateTime createdAt;

  FileVersion({
    required this.version,
    this.createdBy,
    this.changesSummary,
    required this.createdAt,
  });

  factory FileVersion.fromJson(Map<String, dynamic> json) {
    return FileVersion(
      version: json['version'] ?? json['version_number'],
      createdBy: json['created_by'],
      changesSummary: json['changes_summary'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}
