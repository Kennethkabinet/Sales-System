import 'package:http/http.dart' as http;
import 'dart:convert';
import '../config/constants.dart';
import '../models/user.dart';
import '../models/file.dart';
import '../models/formula.dart';
import '../models/audit_log.dart';

/// API Service for all backend communications
class ApiService {
  static String? _authToken;
  static const Duration timeout = AppConfig.apiTimeout;

  static void setAuthToken(String? token) {
    _authToken = token;
  }

  static Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // ============== Helper Methods ==============

  static Future<Map<String, dynamic>> _get(String endpoint) async {
    final response = await http
        .get(Uri.parse('${AppConfig.apiBaseUrl}$endpoint'), headers: _headers)
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _put(String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _delete(String endpoint) async {
    final response = await http
        .delete(Uri.parse('${AppConfig.apiBaseUrl}$endpoint'), headers: _headers)
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final body = jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    } else {
      throw ApiException(
        code: body['error']?['code'] ?? 'ERROR',
        message: body['error']?['message'] ?? 'Request failed',
        statusCode: response.statusCode,
      );
    }
  }

  /// Upload a file using multipart form data
  static Future<Map<String, dynamic>> uploadFile({
    required String filePath,
    required String fileName,
    required String name,
    int? departmentId,
  }) async {
    final uri = Uri.parse('${AppConfig.apiBaseUrl}${ApiEndpoints.uploadFile}');
    final request = http.MultipartRequest('POST', uri);
    
    // Add auth header
    if (_authToken != null) {
      request.headers['Authorization'] = 'Bearer $_authToken';
    }
    
    // Add file
    request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    
    // Add form fields
    request.fields['name'] = name;
    if (departmentId != null) {
      request.fields['department_id'] = departmentId.toString();
    }
    
    final streamedResponse = await request.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamedResponse);
    
    return _handleResponse(response);
  }

  // ============== Legacy Methods ==============

  static Future<String> testConnection() async {
    try {
      final response = await http.get(Uri.parse(AppConfig.apiBaseUrl.replaceAll('/api', '/'))).timeout(timeout);
      if (response.statusCode == 200) {
        return response.body;
      } else {
        throw Exception('Failed: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Connection error: $e');
    }
  }

  static Future<Map<String, dynamic>> getStatus() async {
    return await _get('/status');
  }

  static Future<Map<String, dynamic>> getDbStatus() async {
    return await _get('/db-test');
  }

  // ============== Auth ==============

  static Future<AuthResult> login(String username, String password) async {
    final response = await _post(ApiEndpoints.login, {
      'username': username,
      'password': password,
    });
    return AuthResult.fromJson(response);
  }

  static Future<User> getCurrentUser() async {
    final response = await _get(ApiEndpoints.me);
    return User.fromJson(response['user']);
  }

  static Future<void> logout() async {
    await _post(ApiEndpoints.logout, {});
    _authToken = null;
  }

  // ============== Users (Admin Only) ==============

  static Future<List<User>> getUsers() async {
    final response = await _get(ApiEndpoints.users);
    return (response['users'] as List)
        .map((u) => User.fromJson(u))
        .toList();
  }

  static Future<User> createUser({
    required String username,
    required String email,
    required String password,
    required String fullName,
    required String role,
    int? departmentId,
  }) async {
    final response = await _post(ApiEndpoints.users, {
      'username': username,
      'email': email,
      'password': password,
      'full_name': fullName,
      'role': role,
      if (departmentId != null) 'department_id': departmentId,
    });
    return User.fromJson(response['user']);
  }

  static Future<void> updateUser({
    required int userId,
    String? username,
    String? email,
    String? password,
    String? fullName,
    String? role,
    int? departmentId,
  }) async {
    await _put('${ApiEndpoints.users}/$userId', {
      if (username != null) 'username': username,
      if (email != null) 'email': email,
      if (password != null) 'password': password,
      if (fullName != null) 'full_name': fullName,
      if (role != null) 'role': role,
      if (departmentId != null) 'department_id': departmentId,
    });
  }

  static Future<void> deactivateUser(int userId) async {
    await _delete('${ApiEndpoints.users}/$userId');
  }

  static Future<void> reactivateUser(int userId) async {
    await _put('${ApiEndpoints.users}/$userId/reactivate', {});
  }

  static Future<void> updateUserRole(int userId, String role) async {
    await _put('${ApiEndpoints.users}/$userId/role', {'role': role});
  }

  static Future<List<Department>> getDepartments() async {
    final response = await _get(ApiEndpoints.departments);
    return (response['departments'] as List)
        .map((d) => Department.fromJson(d))
        .toList();
  }

  static Future<List<Role>> getRoles() async {
    final response = await _get(ApiEndpoints.roles);
    return (response['roles'] as List)
        .map((r) => Role.fromJson(r))
        .toList();
  }

  // ============== Files ==============

  static Future<FileListResult> getFiles({int page = 1, int limit = 20, int? departmentId}) async {
    String endpoint = '${ApiEndpoints.files}?page=$page&limit=$limit';
    if (departmentId != null) endpoint += '&department_id=$departmentId';
    final response = await _get(endpoint);
    print('getFiles response: $response'); // Debug
    return FileListResult.fromJson(response);
  }

  static Future<FileDataResult> getFileData(int fileId, {int page = 1, int limit = 50}) async {
    final response = await _get('${ApiEndpoints.files}/$fileId/data?page=$page&limit=$limit');
    return FileDataResult.fromJson(response);
  }

  static Future<void> updateRow(int fileId, int rowId, Map<String, dynamic> values) async {
    await _put('${ApiEndpoints.files}/$fileId/data/$rowId', {'values': values});
  }

  static Future<FileDataRow> addRow(int fileId, Map<String, dynamic> values) async {
    final response = await _post('${ApiEndpoints.files}/$fileId/rows', {'values': values});
    return FileDataRow.fromJson(response['row']);
  }

  static Future<void> deleteRow(int fileId, int rowId) async {
    await _delete('${ApiEndpoints.files}/$fileId/data/$rowId');
  }

  static Future<List<FileVersion>> getFileVersions(int fileId) async {
    final response = await _get('${ApiEndpoints.files}/$fileId/versions');
    return (response['versions'] as List)
        .map((v) => FileVersion.fromJson(v))
        .toList();
  }

  static Future<void> deleteFile(int fileId) async {
    await _delete('${ApiEndpoints.files}/$fileId');
  }

  static Future<FileModel> createFile(String name, {String? fileType}) async {
    final response = await _post(ApiEndpoints.files, {
      'name': name,
      'file_type': fileType ?? 'xlsx',
    });
    return FileModel.fromJson(response['file']);
  }

  // ============== Formulas ==============

  static Future<List<Formula>> getFormulas() async {
    final response = await _get(ApiEndpoints.formulas);
    return (response['formulas'] as List)
        .map((f) => Formula.fromJson(f))
        .toList();
  }

  static Future<Formula> getFormula(int id) async {
    final response = await _get('${ApiEndpoints.formulas}/$id');
    return Formula.fromJson(response['formula']);
  }

  static Future<Formula> createFormula(Formula formula) async {
    final response = await _post(ApiEndpoints.formulas, formula.toJson());
    return Formula.fromJson(response['formula']);
  }

  static Future<Formula> updateFormula(int id, Formula formula) async {
    final response = await _put('${ApiEndpoints.formulas}/$id', formula.toJson());
    return Formula.fromJson(response['formula']);
  }

  static Future<FormulaApplyResult> applyFormula(int formulaId, int fileId, {Map<String, String>? columnMapping}) async {
    final response = await _post('${ApiEndpoints.formulas}/$formulaId/apply', {
      'file_id': fileId,
      if (columnMapping != null) 'column_mapping': columnMapping,
    });
    return FormulaApplyResult.fromJson(response);
  }

  static Future<FormulaPreview> previewFormula(String expression, Map<String, dynamic> testValues) async {
    final response = await _post(ApiEndpoints.formulaPreview, {
      'expression': expression,
      'test_values': testValues,
    });
    return FormulaPreview.fromJson(response);
  }

  static Future<void> deleteFormula(int id) async {
    await _delete('${ApiEndpoints.formulas}/$id');
  }

  // ============== Audit ==============

  static Future<AuditListResult> getAuditLogs({
    int page = 1,
    int limit = 50,
    int? fileId,
    int? userId,
    String? action,
    String? startDate,
    String? endDate,
  }) async {
    String endpoint = '${ApiEndpoints.audit}?page=$page&limit=$limit';
    if (fileId != null) endpoint += '&file_id=$fileId';
    if (userId != null) endpoint += '&user_id=$userId';
    if (action != null) endpoint += '&action=$action';
    if (startDate != null) endpoint += '&start_date=$startDate';
    if (endDate != null) endpoint += '&end_date=$endDate';
    
    final response = await _get(endpoint);
    return AuditListResult.fromJson(response);
  }

  static Future<AuditSummary> getAuditSummary() async {
    final response = await _get(ApiEndpoints.auditSummary);
    return AuditSummary.fromJson(response);
  }

  // ============== Dashboard ==============

  static Future<DashboardStats> getDashboardStats() async {
    final response = await _get(ApiEndpoints.dashboardStats);
    return DashboardStats.fromJson(response);
  }

  static Future<List<RecentActivity>> getRecentActivity({int limit = 10}) async {
    final response = await _get('${ApiEndpoints.recentActivity}?limit=$limit');
    return (response['activity'] as List)
        .map((a) => RecentActivity.fromJson(a))
        .toList();
  }

  // ============== Sheets ==============

  static Future<Map<String, dynamic>> getSheets({int page = 1, int limit = 50}) async {
    return await _get('${ApiEndpoints.sheets}?page=$page&limit=$limit');
  }

  static Future<Map<String, dynamic>> getSheetData(int sheetId) async {
    return await _get('${ApiEndpoints.sheets}/$sheetId');
  }

  static Future<Map<String, dynamic>> createSheet(String name, List<String> columns) async {
    return await _post(ApiEndpoints.sheets, {
      'name': name,
      'columns': columns,
    });
  }

  static Future<Map<String, dynamic>> updateSheet(
    int sheetId,
    String name,
    List<String> columns,
    List<Map<String, dynamic>> rows,
  ) async {
    return await _put('${ApiEndpoints.sheets}/$sheetId', {
      'name': name,
      'columns': columns,
      'rows': rows,
    });
  }

  static Future<void> deleteSheet(int sheetId) async {
    await _delete('${ApiEndpoints.sheets}/$sheetId');
  }

  static Future<List<int>> exportSheet(int sheetId, {String format = 'xlsx'}) async {
    if (_authToken == null) throw Exception('Not authenticated');

    final url = Uri.parse('${AppConfig.apiBaseUrl}${ApiEndpoints.sheets}/$sheetId/export?format=$format');
    final response = await http.get(
      url,
      headers: _headers,
    ).timeout(timeout);

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      final data = jsonDecode(response.body);
      throw ApiException(
        code: data['error']?['code'] ?? 'ERROR',
        message: data['error']?['message'] ?? 'Export failed',
        statusCode: response.statusCode,
      );
    }
  }

  static Future<Map<String, dynamic>> importSheet(
    int sheetId, 
    List<List<dynamic>> data
  ) async {
    return await _post('${ApiEndpoints.sheets}/$sheetId/import', {
      'data': data,
    });
  }

  // Enhanced sheet features for collaborative editing

  /// Toggle sheet visibility to viewers (Admin only)
  static Future<Map<String, dynamic>> toggleSheetVisibility(
    int sheetId, 
    bool showToViewers
  ) async {
    return await _put('${ApiEndpoints.sheets}/$sheetId/visibility', {
      'shown_to_viewers': showToViewers,
    });
  }

  /// Lock sheet for editing
  static Future<Map<String, dynamic>> lockSheet(int sheetId) async {
    return await _post('${ApiEndpoints.sheets}/$sheetId/lock', {});
  }

  /// Unlock sheet
  static Future<Map<String, dynamic>> unlockSheet(int sheetId) async {
    return await _delete('${ApiEndpoints.sheets}/$sheetId/lock');
  }

  /// Start or update edit session
  static Future<Map<String, dynamic>> startEditSession(int sheetId) async {
    return await _post('${ApiEndpoints.sheets}/$sheetId/edit-session', {});
  }

  /// Get current sheet status (locks, active editors)
  static Future<Map<String, dynamic>> getSheetStatus(int sheetId) async {
    return await _get('${ApiEndpoints.sheets}/$sheetId/status');
  }

  static Future<Map<String, dynamic>> getSheetHistory(int sheetId, {int page = 1, int limit = 50}) async {
    return await _get('${ApiEndpoints.sheets}/$sheetId/history?page=$page&limit=$limit');
  }
}

// ============== Result Classes ==============

class AuthResult {
  final bool success;
  final String? token;
  final User? user;
  final String? message;
  final String? error;

  AuthResult({this.success = false, this.token, this.user, this.message, this.error});

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      success: json['success'] ?? false,
      token: json['token'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      message: json['message'],
      error: json['error']?['message'],
    );
  }
}

class FileListResult {
  final List<FileModel> files;
  final Pagination pagination;

  FileListResult({required this.files, required this.pagination});

  factory FileListResult.fromJson(Map<String, dynamic> json) {
    return FileListResult(
      files: (json['files'] as List).map((f) => FileModel.fromJson(f)).toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

class FileDataResult {
  final FileModel file;
  final List<FileDataRow> data;
  final Pagination pagination;

  FileDataResult({required this.file, required this.data, required this.pagination});

  factory FileDataResult.fromJson(Map<String, dynamic> json) {
    return FileDataResult(
      file: FileModel.fromJson(json['file']),
      data: (json['data'] as List).map((d) => FileDataRow.fromJson(d)).toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

class AuditListResult {
  final List<AuditLog> logs;
  final Pagination pagination;

  AuditListResult({required this.logs, required this.pagination});

  factory AuditListResult.fromJson(Map<String, dynamic> json) {
    return AuditListResult(
      logs: (json['logs'] as List).map((l) => AuditLog.fromJson(l)).toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

class Pagination {
  final int page;
  final int limit;
  final int total;
  final int pages;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 50,
      total: json['total'] ?? 0,
      pages: json['pages'] ?? 1,
    );
  }
}

class DashboardStats {
  final int totalFiles;
  final int totalRecords;
  final int activeUsers;
  final int recentChanges;
  final List<Map<String, dynamic>> activityData;
  final List<Map<String, dynamic>> fileTypes;
  final List<Map<String, dynamic>> recentActivity;

  DashboardStats({
    required this.totalFiles,
    required this.totalRecords,
    required this.activeUsers,
    required this.recentChanges,
    required this.activityData,
    required this.fileTypes,
    required this.recentActivity,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] ?? json;
    return DashboardStats(
      totalFiles: stats['total_files'] ?? stats['files_count'] ?? 0,
      totalRecords: stats['total_records'] ?? stats['total_inventory'] ?? 0,
      activeUsers: stats['active_users'] ?? 0,
      recentChanges: stats['recent_changes'] ?? 0,
      activityData: (json['activity_data'] ?? json['sales_trend'] ?? [])
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList(),
      fileTypes: (json['file_types'] ?? [])
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList(),
      recentActivity: (json['recent_activity'] ?? [])
          .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item))
          .toList(),
    );
  }
}

class SalesTrend {
  final DateTime date;
  final double amount;

  SalesTrend({required this.date, required this.amount});

  factory SalesTrend.fromJson(Map<String, dynamic> json) {
    return SalesTrend(
      date: DateTime.parse(json['date']),
      amount: (json['amount'] ?? 0).toDouble(),
    );
  }
}

class TopProduct {
  final String name;
  final int quantity;
  final double revenue;

  TopProduct({required this.name, required this.quantity, required this.revenue});

  factory TopProduct.fromJson(Map<String, dynamic> json) {
    return TopProduct(
      name: json['name'] ?? '',
      quantity: json['quantity'] ?? 0,
      revenue: (json['revenue'] ?? 0).toDouble(),
    );
  }
}

class DepartmentBreakdown {
  final String department;
  final double percentage;

  DepartmentBreakdown({required this.department, required this.percentage});

  factory DepartmentBreakdown.fromJson(Map<String, dynamic> json) {
    return DepartmentBreakdown(
      department: json['department'] ?? '',
      percentage: (json['percentage'] ?? 0).toDouble(),
    );
  }
}

class ApiException implements Exception {
  final String code;
  final String message;
  final int statusCode;

  ApiException({required this.code, required this.message, required this.statusCode});

  @override
  String toString() => message;
}

