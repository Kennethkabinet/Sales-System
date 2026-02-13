/// App configuration constants
class AppConfig {
  static const String appName = 'Sales & Inventory System';
  static const String appVersion = '1.0.0';
  
  // API Configuration
  static const String apiBaseUrl = 'http://localhost:3001/api';
  static const String wsBaseUrl = 'http://localhost:3001';
  
  // Timeouts
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration wsReconnectDelay = Duration(seconds: 3);
  
  // Pagination
  static const int defaultPageSize = 50;
  static const int maxPageSize = 100;
}

/// User roles
class UserRoles {
  static const String admin = 'admin';
  static const String user = 'user';
  static const String viewer = 'viewer';
}

/// API Endpoints
class ApiEndpoints {
  // Auth
  static const String login = '/auth/login';
  static const String register = '/auth/register';
  static const String me = '/auth/me';
  static const String logout = '/auth/logout';
  
  // Users
  static const String users = '/users';
  static const String departments = '/users/meta/departments';
  static const String roles = '/users/meta/roles';
  
  // Files
  static const String files = '/files';
  static const String uploadFile = '/files/upload';
  
  // Folders
  static const String folders = '/files/folders';
  
  // Formulas
  static const String formulas = '/formulas';
  static const String formulaPreview = '/formulas/preview';
  
  // Audit
  static const String audit = '/audit';
  static const String auditSummary = '/audit/summary';
  
  // Dashboard
  static const String dashboardStats = '/dashboard/stats';
  static const String recentActivity = '/dashboard/recent-activity';
  
  // Sheets
  static const String sheets = '/sheets';
}
