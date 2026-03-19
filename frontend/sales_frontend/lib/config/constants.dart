import 'package:flutter/material.dart';

/// App brand colours – Orange & Blue theme
///
/// Primary Orange: 0xFFE44408  (Brand Orange)
/// Primary Blue  : 0xFF1C2172  (Brand Navy Blue)
class AppColors {
  // ── Primary brand colours ──────────────────────────────────────
  static const Color primaryOrange = Color(0xFFE44408); // main orange
  static const Color primaryBlue = Color(0xFF1C2172); // main navy blue
  static const Color primaryRed =
      Color(0xFFE44408); // alias for orange (backward compatibility)

  // ── Lighter tints (backgrounds, chips) ────────────────────────
  static const Color lightOrange = Color(0xFFFFF3E0); // orange-tinted bg
  static const Color lightBlue = Color(0xFFE8EAF6); // blue-tinted bg
  static const Color lightRed = Color(0xFFFFF3E0); // alias for lightOrange

  // ── Header gradient ────────────────────────────────────────────
  static const Color gradientStart = Color(0xFFE44408); // orange
  static const Color gradientEnd = Color(0xFF1C2172); // navy blue

  // ── Neutrals ──────────────────────────────────────────────────
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color darkText = Color(0xFF1F2937);
  static const Color grayText = Color(0xFF6B7280);
  static const Color lightGray = Color(0xFF9CA3AF);
  static const Color border = Color(0xFFE5E7EB);
  static const Color bgLight = Color(0xFFF9FAFB);
}

/// App configuration constants
class AppConfig {
  static const String appName = 'Synergy Graphics';
  static const String appVersion = '1.0.0';

  // API Configuration
  static const String apiBaseUrl = 'http://192.168.3.224:3000/api';
  static const String wsBaseUrl = 'http://192.168.3.224:3000';

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
  static const String inventoryOverview = '/dashboard/inventory-overview';
  static const String inventorySheets = '/dashboard/inventory-sheets';

  // Sheets
  static const String sheets = '/sheets';
  static const String sheetLinks = '/sheet-links';
  static const String workspaces = '/workspaces';

  // Inventory
  static const String inventoryStock = '/inventory/stock';
  static const String inventoryProducts = '/inventory/products';
  static const String inventoryTransactions = '/inventory/transactions';
  static const String inventoryDates = '/inventory/dates';
  static const String inventoryAudit = '/inventory/audit';
  static const String inventoryRecalculate = '/inventory/recalculate';
  static const String productionLines = '/inventory/production-lines';
}
