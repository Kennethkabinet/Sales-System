import 'package:flutter/material.dart';

/// App brand colours – Blue & Red theme
///
/// Primary Blue  : 0xFF1565C0  (Material Blue 800)
/// Primary Red   : 0xFFD32F2F  (Material Red 700)
class AppColors {
  // ── Primary brand colours ──────────────────────────────────────
  static const Color primaryBlue = Color(0xFF1565C0); // main blue
  static const Color primaryRed = Color(0xFFD32F2F); // main red

  // ── Lighter tints (backgrounds, chips) ────────────────────────
  static const Color lightBlue = Color(0xFFE3F2FD); // blue-tinted bg
  static const Color lightRed = Color(0xFFFFEBEE); // red-tinted bg

  // ── Header gradient ────────────────────────────────────────────
  static const Color gradientStart = Color(0xFF1565C0); // blue
  static const Color gradientEnd = Color(0xFFD32F2F); // red

  // ── Neutrals ──────────────────────────────────────────────────
  static const Color white = Color(0xFFFFFFFF);
  static const Color darkText = Color(0xFF202124);
  static const Color grayText = Color(0xFF5F6368);
  static const Color border = Color(0xFFE8EAED);
  static const Color bgLight = Color(0xFFF8F9FA);
}

/// App configuration constants
class AppConfig {
  static const String appName = 'Synergy Graphics';
  static const String appVersion = '1.0.0';

  // API Configuration
  static const String apiBaseUrl = 'http://localhost:3000/api';
  static const String wsBaseUrl = 'http://localhost:3000';

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

  // Inventory
  static const String inventoryStock = '/inventory/stock';
  static const String inventoryProducts = '/inventory/products';
  static const String inventoryTransactions = '/inventory/transactions';
  static const String inventoryDates = '/inventory/dates';
  static const String inventoryAudit = '/inventory/audit';
}
