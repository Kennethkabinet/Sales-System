import 'package:flutter/foundation.dart';
import '../models/file.dart';
import '../models/formula.dart';
import '../models/audit_log.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Data state provider for files, formulas, and realtime updates
class DataProvider extends ChangeNotifier {
  // Auth
  String? _token;
  String? _userId;

  // Files
  List<FileModel> _files = [];
  FileModel? _currentFile;
  List<Map<String, dynamic>> _fileData = [];
  List<String> _fileColumns = [];
  Pagination? _filePagination;
  Pagination? _dataPagination;

  // Formulas
  List<Formula> _formulas = [];
  
  // Audit
  List<AuditLog> _auditLogs = [];

  // Dashboard
  DashboardStats? _dashboardStats;
  AuditSummary? _auditSummary;

  // Collaboration
  List<ActiveUser> _activeUsers = [];
  Map<String, String> _lockedRows = {}; // rowId -> userId

  // State
  bool _isLoading = false;
  String? _error;

  // Getters
  List<FileModel> get files => _files;
  FileModel? get currentFile => _currentFile;
  int? get currentFileId => _currentFile?.id;
  List<Map<String, dynamic>> get fileData => _fileData;
  List<String> get fileColumns => _fileColumns;
  List<Formula> get formulas => _formulas;
  List<AuditLog> get auditLogs => _auditLogs;
  DashboardStats? get dashboardStats => _dashboardStats;
  AuditSummary? get auditSummary => _auditSummary;
  List<ActiveUser> get activeUsers => _activeUsers;
  Map<String, String> get lockedRows => _lockedRows;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Pagination? get filePagination => _filePagination;
  Pagination? get dataPagination => _dataPagination;

  DataProvider() {
    _setupSocketListeners();
  }

  void setAuth(String token, String userId) {
    _token = token;
    _userId = userId;
    ApiService.setAuthToken(token);
    SocketService.instance.connect(token);
  }

  void _setupSocketListeners() {
    final socket = SocketService.instance;

    socket.onUserJoined = (data) {
      final user = ActiveUser(
        id: data['user_id']?.toString() ?? '',
        name: data['username'] ?? '',
      );
      if (!_activeUsers.any((u) => u.id == user.id)) {
        _activeUsers.add(user);
        notifyListeners();
      }
    };

    socket.onUserLeft = (data) {
      _activeUsers.removeWhere((u) => u.id == data['user_id']?.toString());
      notifyListeners();
    };

    socket.onRowLocked = (data) {
      _lockedRows[data['row_id']?.toString() ?? ''] = data['locked_by']?.toString() ?? '';
      notifyListeners();
    };

    socket.onRowUnlocked = (data) {
      _lockedRows.remove(data['row_id']?.toString());
      notifyListeners();
    };

    socket.onRowUpdated = (data) {
      final rowId = data['row_id']?.toString();
      final values = Map<String, dynamic>.from(data['values'] ?? {});
      
      final index = _fileData.indexWhere((r) => r['id']?.toString() == rowId);
      if (index != -1) {
        _fileData[index] = {..._fileData[index], ...values};
        notifyListeners();
      }
    };

    socket.onActiveUsers = (data) {
      final users = (data['users'] as List? ?? [])
          .map((u) => ActiveUser(
            id: u['user_id']?.toString() ?? '',
            name: u['username']?.toString() ?? '',
          ))
          .toList();
      _activeUsers = users;
      notifyListeners();
    };

    socket.onError = (data) {
      _error = data['message'] ?? 'Socket error';
      notifyListeners();
    };
  }

  // ============== Files ==============

  Future<void> loadFiles({int page = 1, int? departmentId}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await ApiService.getFiles(page: page, departmentId: departmentId);
      _files = result.files;
      _filePagination = result.pagination;
      print('loadFiles: Loaded ${_files.length} files'); // Debug
    } catch (e) {
      _error = e.toString();
      print('loadFiles error: $_error'); // Debug
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> uploadFile(String filePath, String fileName, String name) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.uploadFile(
        filePath: filePath,
        fileName: fileName,
        name: name,
      );
      
      print('uploadFile response: $response'); // Debug
      
      if (response['success'] == true && response['file'] != null) {
        // Reload files to get the new file in the list
        await loadFiles();
        return true;
      }
      return false;
    } catch (e) {
      _error = e.toString();
      print('uploadFile error: $_error'); // Debug
      notifyListeners();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createFile(String name) async {
    _isLoading = true;
    notifyListeners();

    try {
      final newFile = await ApiService.createFile(name);
      _files.insert(0, newFile);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteFile(int fileId) async {
    try {
      await ApiService.deleteFile(fileId);
      _files.removeWhere((f) => f.id == fileId);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> loadFileData(int fileId, String userId, {int page = 1}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Leave previous file if any
      if (_currentFile != null && _currentFile!.id != fileId) {
        SocketService.instance.leaveFile(_currentFile!.id);
      }

      final result = await ApiService.getFileData(fileId, page: page);
      _currentFile = result.file;
      _fileColumns = result.file?.columns ?? [];
      _fileData = result.data.map((row) => {
        ...row.values,
        'id': row.rowId.toString(),
      }).toList();
      _dataPagination = result.pagination;

      // Join file for real-time updates
      SocketService.instance.joinFile(fileId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateRow(String rowId, Map<String, dynamic> values) async {
    if (_currentFile == null) return false;

    try {
      final intRowId = int.tryParse(rowId) ?? 0;
      await ApiService.updateRow(_currentFile!.id, intRowId, values);
      
      // Update local data
      final index = _fileData.indexWhere((r) => r['id']?.toString() == rowId);
      if (index != -1) {
        _fileData[index] = {..._fileData[index], ...values};
        notifyListeners();
      }

      // Broadcast to others via socket
      SocketService.instance.updateRow(_currentFile!.id, intRowId, values);
      
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addRow(Map<String, dynamic> values) async {
    if (_currentFile == null) return false;

    try {
      final newRow = await ApiService.addRow(_currentFile!.id, values);
      _fileData.add({
        ...newRow.values,
        'id': newRow.rowId.toString(),
      });
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteRow(String rowId) async {
    if (_currentFile == null) return false;

    try {
      final intRowId = int.tryParse(rowId) ?? 0;
      await ApiService.deleteRow(_currentFile!.id, intRowId);
      _fileData.removeWhere((r) => r['id']?.toString() == rowId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  void lockRow(String rowId) {
    if (_currentFile != null) {
      final intRowId = int.tryParse(rowId) ?? 0;
      SocketService.instance.lockRow(_currentFile!.id, intRowId);
      _lockedRows[rowId] = _userId ?? '';
      notifyListeners();
    }
  }

  void unlockRow(String rowId) {
    if (_currentFile != null) {
      final intRowId = int.tryParse(rowId) ?? 0;
      SocketService.instance.unlockRow(_currentFile!.id, intRowId);
      _lockedRows.remove(rowId);
      notifyListeners();
    }
  }

  void leaveFile() {
    if (_currentFile != null) {
      SocketService.instance.leaveFile(_currentFile!.id);
      _currentFile = null;
      _fileData = [];
      _fileColumns = [];
      _activeUsers = [];
      _lockedRows = {};
      notifyListeners();
    }
  }

  // ============== Formulas ==============

  Future<void> loadFormulas() async {
    _isLoading = true;
    notifyListeners();

    try {
      _formulas = await ApiService.getFormulas();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createFormula(String name, String expression, String? description) async {
    try {
      final formula = Formula(
        id: 0,
        name: name,
        expression: expression,
        description: description,
        outputColumn: 'result',
      );
      final newFormula = await ApiService.createFormula(formula);
      _formulas.add(newFormula);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateFormula(int id, String name, String expression, String? description) async {
    try {
      final formula = Formula(
        id: id,
        name: name,
        expression: expression,
        description: description,
        outputColumn: 'result',
      );
      final updatedFormula = await ApiService.updateFormula(id, formula);
      final index = _formulas.indexWhere((f) => f.id == id);
      if (index != -1) {
        _formulas[index] = updatedFormula;
      }
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteFormula(int id) async {
    try {
      await ApiService.deleteFormula(id);
      _formulas.removeWhere((f) => f.id == id);
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<FormulaApplyResult?> applyFormula(int formulaId, {Map<String, String>? columnMapping}) async {
    if (_currentFile == null) return null;

    try {
      final result = await ApiService.applyFormula(
        formulaId, 
        _currentFile!.id,
        columnMapping: columnMapping,
      );
      
      if (result.success) {
        // Reload file data to see results
        await loadFileData(_currentFile!.id, _userId ?? '');
      }
      
      return result;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  // ============== Dashboard ==============

  Future<void> loadDashboard() async {
    _isLoading = true;
    notifyListeners();

    try {
      _dashboardStats = await ApiService.getDashboardStats();
      _auditSummary = await ApiService.getAuditSummary();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============== Audit Logs ==============

  Future<void> loadAuditLogs({
    String? action,
    String? entity,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await ApiService.getAuditLogs(
        action: action,
        startDate: startDate?.toIso8601String(),
        endDate: endDate?.toIso8601String(),
      );
      _auditLogs = result.logs;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============== Utilities ==============

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    leaveFile();
    _files = [];
    _formulas = [];
    _auditLogs = [];
    _dashboardStats = null;
    _auditSummary = null;
    _error = null;
    notifyListeners();
  }
}

/// Active user model for collaboration
class ActiveUser {
  final String id;
  final String name;

  ActiveUser({
    required this.id,
    required this.name,
  });
}
