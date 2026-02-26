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

  static Future<Map<String, dynamic>> _post(
      String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .post(
          Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _put(
      String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .put(
          Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _patch(
      String endpoint, Map<String, dynamic> body) async {
    final response = await http
        .patch(
          Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
          headers: _headers,
          body: jsonEncode(body),
        )
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Future<Map<String, dynamic>> _delete(String endpoint) async {
    final response = await http
        .delete(Uri.parse('${AppConfig.apiBaseUrl}$endpoint'),
            headers: _headers)
        .timeout(timeout);
    return _handleResponse(response);
  }

  static Map<String, dynamic> _handleResponse(http.Response response) {
    final rawBody = response.body.trim();
    if (rawBody.isEmpty) {
      throw ApiException(
        code: 'EMPTY_RESPONSE',
        message:
            'Server returned an empty response (status ${response.statusCode}). '
            'The backend may be down or restarting.',
        statusCode: response.statusCode,
      );
    }
    late final dynamic body;
    try {
      body = jsonDecode(rawBody);
    } catch (_) {
      throw ApiException(
        code: 'INVALID_JSON',
        message:
            'Server returned invalid JSON (status ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (body is Map<String, dynamic>) return body;
      return {'data': body};
    } else {
      final errMap = body is Map ? body : null;
      final errBlock = errMap != null && errMap['error'] is Map
          ? errMap['error'] as Map
          : null;
      throw ApiException(
        code: (errBlock?['code'] as String?) ?? 'ERROR',
        message: (errBlock?['message'] as String?) ?? 'Request failed',
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
    request.files.add(await http.MultipartFile.fromPath('file', filePath,
        filename: fileName));

    // Add form fields
    request.fields['name'] = name;
    if (departmentId != null) {
      request.fields['department_id'] = departmentId.toString();
    }

    final streamedResponse =
        await request.send().timeout(const Duration(minutes: 2));
    final response = await http.Response.fromStream(streamedResponse);

    return _handleResponse(response);
  }

  // ============== Legacy Methods ==============

  static Future<String> testConnection() async {
    try {
      final response = await http
          .get(Uri.parse(AppConfig.apiBaseUrl.replaceAll('/api', '/')))
          .timeout(timeout);
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

  static Future<AuthResult> register({
    required String username,
    required String email,
    required String password,
    required String fullName,
  }) async {
    final response = await _post(ApiEndpoints.register, {
      'username': username,
      'email': email,
      'password': password,
      'full_name': fullName,
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
    return (response['users'] as List).map((u) => User.fromJson(u)).toList();
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

  static Future<void> deleteUserPermanently(int userId) async {
    await _delete('${ApiEndpoints.users}/$userId/permanent');
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

  static Future<Department> createDepartment({
    required String name,
    String? description,
  }) async {
    final response = await _post(ApiEndpoints.departments, {
      'name': name,
      if (description != null) 'description': description,
    });
    return Department.fromJson(response['department']);
  }

  static Future<void> deleteDepartment(int departmentId) async {
    await _delete('${ApiEndpoints.departments}/$departmentId');
  }

  static Future<List<Role>> getRoles() async {
    final response = await _get(ApiEndpoints.roles);
    return (response['roles'] as List).map((r) => Role.fromJson(r)).toList();
  }

  // ============== Files ==============

  static Future<FileListResult> getFiles(
      {int page = 1, int limit = 20, int? departmentId, int? folderId}) async {
    String endpoint = '${ApiEndpoints.files}?page=$page&limit=$limit';
    if (departmentId != null) endpoint += '&department_id=$departmentId';
    if (folderId != null) {
      endpoint += '&folder_id=$folderId';
    } else {
      endpoint += '&folder_id=root';
    }
    final response = await _get(endpoint);
    return FileListResult.fromJson(response);
  }

  static Future<FileDataResult> getFileData(int fileId,
      {int page = 1, int limit = 50}) async {
    final response = await _get(
        '${ApiEndpoints.files}/$fileId/data?page=$page&limit=$limit');
    return FileDataResult.fromJson(response);
  }

  static Future<void> updateRow(
      int fileId, int rowId, Map<String, dynamic> values) async {
    await _put('${ApiEndpoints.files}/$fileId/data/$rowId', {'values': values});
  }

  static Future<FileDataRow> addRow(
      int fileId, Map<String, dynamic> values) async {
    final response =
        await _post('${ApiEndpoints.files}/$fileId/rows', {'values': values});
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

  static Future<FileModel> createFile(String name,
      {String? fileType, int? folderId}) async {
    final response = await _post(ApiEndpoints.files, {
      'name': name,
      'file_type': fileType ?? 'xlsx',
      if (folderId != null) 'folder_id': folderId,
    });
    return FileModel.fromJson(response['file']);
  }

  // ============== Folders ==============

  static Future<FolderModel> createFolder(String name, {int? parentId}) async {
    final response = await _post(ApiEndpoints.folders, {
      'name': name,
      if (parentId != null) 'parent_id': parentId,
    });
    return FolderModel.fromJson(response['folder']);
  }

  static Future<void> renameFolder(int folderId, String name) async {
    await _patch('${ApiEndpoints.folders}/$folderId/rename', {'name': name});
  }

  static Future<void> deleteFolder(int folderId) async {
    await _delete('${ApiEndpoints.folders}/$folderId');
  }

  static Future<void> renameFile(int fileId, String name) async {
    await _patch('${ApiEndpoints.files}/$fileId/rename', {'name': name});
  }

  static Future<void> moveFile(int fileId, {int? folderId}) async {
    await _patch('${ApiEndpoints.files}/$fileId/move', {
      'folder_id': folderId,
    });
  }

  static Future<List<int>> downloadFile(int fileId) async {
    if (_authToken == null) throw Exception('Not authenticated');
    final url = Uri.parse(
        '${AppConfig.apiBaseUrl}${ApiEndpoints.files}/$fileId/download');
    final response = await http.get(url, headers: _headers).timeout(timeout);
    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      final data = jsonDecode(response.body);
      throw ApiException(
        code: data['error']?['code'] ?? 'ERROR',
        message: data['error']?['message'] ?? 'Download failed',
        statusCode: response.statusCode,
      );
    }
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
    final response =
        await _put('${ApiEndpoints.formulas}/$id', formula.toJson());
    return Formula.fromJson(response['formula']);
  }

  static Future<FormulaApplyResult> applyFormula(int formulaId, int fileId,
      {Map<String, String>? columnMapping}) async {
    final response = await _post('${ApiEndpoints.formulas}/$formulaId/apply', {
      'file_id': fileId,
      if (columnMapping != null) 'column_mapping': columnMapping,
    });
    return FormulaApplyResult.fromJson(response);
  }

  static Future<FormulaPreview> previewFormula(
      String expression, Map<String, dynamic> testValues) async {
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

  static Future<List<RecentActivity>> getRecentActivity(
      {int limit = 10}) async {
    final response = await _get('${ApiEndpoints.recentActivity}?limit=$limit');
    return (response['activity'] as List)
        .map((a) => RecentActivity.fromJson(a))
        .toList();
  }

  // ============== Sheets ==============

  static Future<Map<String, dynamic>> getSheets(
      {int page = 1,
      int limit = 50,
      int? folderId,
      bool rootOnly = false}) async {
    String url = '${ApiEndpoints.sheets}?page=$page&limit=$limit';
    if (folderId != null) {
      url += '&folder_id=$folderId';
    } else if (rootOnly) {
      url += '&folder_id=root';
    }
    return await _get(url);
  }

  static Future<Map<String, dynamic>> getSheetFolders() async {
    return await _get('${ApiEndpoints.sheets}/folders');
  }

  static Future<Map<String, dynamic>> moveSheetToFolder(
      int sheetId, int? folderId) async {
    return await _put('${ApiEndpoints.sheets}/$sheetId/move', {
      'folder_id': folderId,
    });
  }

  static Future<Map<String, dynamic>> getSheetData(int sheetId) async {
    return await _get('${ApiEndpoints.sheets}/$sheetId');
  }

  static Future<Map<String, dynamic>> createSheet(
      String name, List<String> columns) async {
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

  static Future<Map<String, dynamic>> renameSheet(
      int sheetId, String name) async {
    return await _patch('${ApiEndpoints.sheets}/$sheetId/rename', {
      'name': name,
    });
  }

  static Future<void> deleteSheet(int sheetId) async {
    await _delete('${ApiEndpoints.sheets}/$sheetId');
  }

  static Future<void> deleteSheetFolder(int folderId) async {
    await _delete('${ApiEndpoints.sheets}/folders/$folderId');
  }

  static Future<List<int>> exportSheet(int sheetId,
      {String format = 'xlsx'}) async {
    if (_authToken == null) throw Exception('Not authenticated');

    final url = Uri.parse(
        '${AppConfig.apiBaseUrl}${ApiEndpoints.sheets}/$sheetId/export?format=$format');
    final response = await http
        .get(
          url,
          headers: _headers,
        )
        .timeout(timeout);

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

  static Future<Map<String, dynamic>> importSheetFromFile({
    required String filePath,
    required String fileName,
    String? sheetName,
  }) async {
    if (_authToken == null) throw Exception('Not authenticated');
    final url =
        Uri.parse('${AppConfig.apiBaseUrl}${ApiEndpoints.sheets}/import-file');
    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $_authToken'
      ..fields['name'] = sheetName ??
          fileName.replaceAll(
              RegExp(r'\.(xlsx?|csv)$', caseSensitive: false), '')
      ..files.add(await http.MultipartFile.fromPath('file', filePath,
          filename: fileName));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      return body;
    } else {
      throw ApiException(
        code: body['error']?['code'] ?? 'ERROR',
        message: body['error']?['message'] ?? 'Import failed',
        statusCode: response.statusCode,
      );
    }
  }

  static Future<Map<String, dynamic>> importSheetFromBytes({
    required List<int> bytes,
    required String fileName,
    String? sheetName,
  }) async {
    if (_authToken == null) throw Exception('Not authenticated');
    final url =
        Uri.parse('${AppConfig.apiBaseUrl}${ApiEndpoints.sheets}/import-file');
    final request = http.MultipartRequest('POST', url)
      ..headers['Authorization'] = 'Bearer $_authToken'
      ..fields['name'] = sheetName ??
          fileName.replaceAll(
              RegExp(r'\.(xlsx?|csv)$', caseSensitive: false), '')
      ..files
          .add(http.MultipartFile.fromBytes('file', bytes, filename: fileName));
    final streamed = await request.send().timeout(const Duration(seconds: 60));
    final response = await http.Response.fromStream(streamed);
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode == 200 || response.statusCode == 201) {
      return body;
    } else {
      throw ApiException(
        code: body['error']?['code'] ?? 'ERROR',
        message: body['error']?['message'] ?? 'Import failed',
        statusCode: response.statusCode,
      );
    }
  }

  static Future<Map<String, dynamic>> importSheet(
      int sheetId, List<List<dynamic>> data) async {
    return await _post('${ApiEndpoints.sheets}/$sheetId/import', {
      'data': data,
    });
  }

  // Enhanced sheet features for collaborative editing

  /// Toggle sheet visibility to viewers (Admin only)
  static Future<Map<String, dynamic>> toggleSheetVisibility(
      int sheetId, bool showToViewers) async {
    return await _put('${ApiEndpoints.sheets}/$sheetId/visibility', {
      'shown_to_viewers': showToViewers,
    });
  }

  /// Set or remove a sheet password (Admin/Editor only; pass null to remove)
  static Future<Map<String, dynamic>> setSheetPassword(
      int sheetId, String? password) async {
    return await _put(
        '${ApiEndpoints.sheets}/$sheetId/set-password', {'password': password});
  }

  /// Set or remove a folder password (Admin/Editor only; pass null to remove)
  static Future<Map<String, dynamic>> setFolderPassword(
      int folderId, String? password) async {
    return await _put('${ApiEndpoints.sheets}/folders/$folderId/set-password',
        {'password': password});
  }

  /// Verify sheet password — returns success:true if correct
  static Future<Map<String, dynamic>> verifySheetPassword(
      int sheetId, String password) async {
    return await _post('${ApiEndpoints.sheets}/$sheetId/verify-password',
        {'password': password});
  }

  /// Verify folder password — returns success:true if correct
  static Future<Map<String, dynamic>> verifyFolderPassword(
      int folderId, String password) async {
    return await _post(
        '${ApiEndpoints.sheets}/folders/$folderId/verify-password',
        {'password': password});
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

  /// Heartbeat: mark current user as active in a sheet.
  static Future<Map<String, dynamic>> heartbeatSheetActiveUser(
      int sheetId) async {
    return await _post(
        '${ApiEndpoints.sheets}/$sheetId/active-users/heartbeat', {});
  }

  /// Get active users in a sheet (last 10 seconds).
  static Future<List<Map<String, dynamic>>> getSheetActiveUsers(
      int sheetId) async {
    final response = await _get('${ApiEndpoints.sheets}/$sheetId/active-users');
    return List<Map<String, dynamic>>.from(response['users'] as List? ?? []);
  }

  static Future<Map<String, dynamic>> getSheetHistory(int sheetId,
      {int page = 1, int limit = 50}) async {
    return await _get(
        '${ApiEndpoints.sheets}/$sheetId/history?page=$page&limit=$limit');
  }

  // ── Edit Requests (Admin Approval Workflow) ──

  /// Get edit requests for a sheet (admin only).
  /// [status]: 'pending' | 'approved' | 'rejected' | null (all)
  static Future<List<Map<String, dynamic>>> getEditRequests(int sheetId,
      {String? status}) async {
    String url = '${ApiEndpoints.sheets}/$sheetId/edit-requests';
    if (status != null) url += '?status=$status';
    final response = await _get(url);
    return List<Map<String, dynamic>>.from(response['requests'] as List);
  }

  /// Admin fetches all edit requests across every sheet.
  static Future<List<Map<String, dynamic>>> getAllEditRequests(
      {String? status}) async {
    String url = '${ApiEndpoints.sheets}/edit-requests/all';
    if (status != null) url += '?status=$status';
    final response = await _get(url);
    return List<Map<String, dynamic>>.from(response['requests'] as List);
  }

  /// Submit an edit request for a locked inventory cell.
  static Future<Map<String, dynamic>> submitEditRequest({
    required int sheetId,
    required int rowNumber,
    required String columnName,
    String? cellReference,
    String? currentValue,
    String? proposedValue,
  }) async {
    return await _post('${ApiEndpoints.sheets}/$sheetId/edit-requests', {
      'row_number': rowNumber,
      'column_name': columnName,
      if (cellReference != null) 'cell_reference': cellReference,
      if (currentValue != null) 'current_value': currentValue,
      if (proposedValue != null) 'proposed_value': proposedValue,
    });
  }

  /// Admin approves or rejects an edit request.
  static Future<Map<String, dynamic>> respondToEditRequest({
    required int sheetId,
    required int requestId,
    required bool approved,
    String? rejectReason,
  }) async {
    return await _put(
        '${ApiEndpoints.sheets}/$sheetId/edit-requests/$requestId', {
      'approved': approved,
      if (rejectReason != null) 'reject_reason': rejectReason,
    });
  }

  /// Admin deletes a resolved (approved or rejected) edit request.
  static Future<void> deleteEditRequest(int requestId) async {
    await _delete('${ApiEndpoints.sheets}/edit-requests/$requestId');
  }

  /// Get sheet-level cell audit trail.
  static Future<Map<String, dynamic>> getSheetAudit(int sheetId,
      {int page = 1, int limit = 50, String? cellReference}) async {
    String url =
        '${ApiEndpoints.sheets}/$sheetId/audit?page=$page&limit=$limit';
    if (cellReference != null) url += '&cell_reference=$cellReference';
    return await _get(url);
  }

  // ============== Inventory ==============

  /// Current stock snapshot for all active products
  static Future<Map<String, dynamic>> getInventoryStock() async {
    return await _get(ApiEndpoints.inventoryStock);
  }

  /// All active products (admin sees inactive too)
  static Future<Map<String, dynamic>> getInventoryProducts() async {
    return await _get(ApiEndpoints.inventoryProducts);
  }

  /// Create product (admin only)
  static Future<Map<String, dynamic>> createInventoryProduct({
    required String productName,
    String? qcCode,
    int maintainingQty = 0,
    int criticalQty = 0,
  }) async {
    return await _post(ApiEndpoints.inventoryProducts, {
      'product_name': productName,
      'qc_code': qcCode,
      'maintaining_qty': maintainingQty,
      'critical_qty': criticalQty,
    });
  }

  /// Update product (admin only)
  static Future<Map<String, dynamic>> updateInventoryProduct(
      int id, Map<String, dynamic> body) async {
    return await _put('${ApiEndpoints.inventoryProducts}/$id', body);
  }

  /// Soft-delete product (admin only)
  static Future<Map<String, dynamic>> deleteInventoryProduct(int id) async {
    return await _delete('${ApiEndpoints.inventoryProducts}/$id');
  }

  /// Transactions: optional date filter like '2026-02-18'
  static Future<Map<String, dynamic>> getInventoryTransactions(
      {String? date, String? from, String? to}) async {
    final params = <String, String>{};
    if (date != null) params['date'] = date;
    if (from != null) params['from'] = from;
    if (to != null) params['to'] = to;
    final query = params.isNotEmpty
        ? '?${params.entries.map((e) => '${e.key}=${e.value}').join('&')}'
        : '';
    return await _get('${ApiEndpoints.inventoryTransactions}$query');
  }

  /// Distinct dates with transactions (for accordion)
  static Future<Map<String, dynamic>> getInventoryDates() async {
    return await _get(ApiEndpoints.inventoryDates);
  }

  /// Record a new transaction
  static Future<Map<String, dynamic>> createInventoryTransaction({
    required int productId,
    int qtyIn = 0,
    int qtyOut = 0,
    String? referenceNo,
    String? remarks,
    String? transactionDate,
  }) async {
    return await _post(ApiEndpoints.inventoryTransactions, {
      'product_id': productId,
      'qty_in': qtyIn,
      'qty_out': qtyOut,
      if (referenceNo != null) 'reference_no': referenceNo,
      if (remarks != null) 'remarks': remarks,
      if (transactionDate != null) 'transaction_date': transactionDate,
    });
  }

  /// Update transaction
  static Future<Map<String, dynamic>> updateInventoryTransaction(
      int id, Map<String, dynamic> body) async {
    return await _put('${ApiEndpoints.inventoryTransactions}/$id', body);
  }

  /// Delete transaction
  static Future<Map<String, dynamic>> deleteInventoryTransaction(int id) async {
    return await _delete('${ApiEndpoints.inventoryTransactions}/$id');
  }

  /// Inventory audit log (admin only)
  static Future<Map<String, dynamic>> getInventoryAudit(
      {int page = 1, int limit = 100}) async {
    return await _get('${ApiEndpoints.inventoryAudit}?page=$page&limit=$limit');
  }
}

// ============== Result Classes ==============

class AuthResult {
  final bool success;
  final String? token;
  final User? user;
  final String? message;
  final String? error;

  AuthResult(
      {this.success = false, this.token, this.user, this.message, this.error});

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
  final List<FolderModel> folders;
  final Pagination pagination;

  FileListResult(
      {required this.files, required this.folders, required this.pagination});

  factory FileListResult.fromJson(Map<String, dynamic> json) {
    return FileListResult(
      files: (json['files'] as List? ?? [])
          .map((f) => FileModel.fromJson(f))
          .toList(),
      folders: (json['folders'] as List? ?? [])
          .map((f) => FolderModel.fromJson(f))
          .toList(),
      pagination: Pagination.fromJson(json['pagination'] ?? {}),
    );
  }
}

class FileDataResult {
  final FileModel file;
  final List<FileDataRow> data;
  final Pagination pagination;

  FileDataResult(
      {required this.file, required this.data, required this.pagination});

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

class DashboardActiveUser {
  final int id;
  final String username;
  final String fullName;
  final String email;
  final String role;
  final String? lastLogin;

  DashboardActiveUser({
    required this.id,
    required this.username,
    required this.fullName,
    required this.email,
    required this.role,
    this.lastLogin,
  });

  factory DashboardActiveUser.fromJson(Map<String, dynamic> json) {
    return DashboardActiveUser(
      id: json['id'] ?? 0,
      username: json['username'] ?? '',
      fullName: json['full_name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      lastLogin: json['last_login']?.toString(),
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
  final List<DashboardActiveUser> activeUsersList;

  DashboardStats({
    required this.totalFiles,
    required this.totalRecords,
    required this.activeUsers,
    required this.recentChanges,
    required this.activityData,
    required this.fileTypes,
    required this.recentActivity,
    required this.activeUsersList,
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
      activeUsersList: (json['active_users_list'] ?? [])
          .map<DashboardActiveUser>((item) =>
              DashboardActiveUser.fromJson(Map<String, dynamic>.from(item)))
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

  TopProduct(
      {required this.name, required this.quantity, required this.revenue});

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

  ApiException(
      {required this.code, required this.message, required this.statusCode});

  @override
  String toString() => message;
}
