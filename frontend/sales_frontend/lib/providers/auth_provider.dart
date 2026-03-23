import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/socket_service.dart';

/// Authentication state provider
class AuthProvider extends ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;
  bool get isViewer => _user?.isViewer ?? false;
  bool get canEdit => _user?.canEdit ?? false;

  static String _toFriendlyError(Object error) {
    var msg = error.toString();
    if (msg.startsWith('Exception: ')) {
      msg = msg.substring('Exception: '.length);
    }

    final lower = msg.toLowerCase();
    final isNetwork = lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('failed host lookup') ||
        lower.contains('no route to host') ||
        lower.contains('errno = 1225');
    if (isNetwork) {
      return 'Can\'t connect to the server. Please make sure the backend is running and the API base URL is correct.'
          ' If you\'re using an Android emulator, use 10.0.2.2 instead of localhost.';
    }

    final isTimeout = lower.contains('timed out') || lower.contains('timeout');
    if (isTimeout) {
      return 'The server took too long to respond. Please try again.';
    }

    return msg;
  }

  /// Initialize auth state from stored token
  Future<void> initialize() async {
    _isLoading = true;

    _setupAuthRevocationHandlers();

    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('auth_token');

      if (_token != null) {
        ApiService.setAuthToken(_token);
        _user = await ApiService.getCurrentUser();

        // Connect to WebSocket
        SocketService.instance.connect(_token!);
      }
    } catch (e) {
      // Token might be expired
      await _clearAuth();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Login with username and password
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _setupAuthRevocationHandlers();

    try {
      final result = await ApiService.login(username, password);

      if (result.success && result.token != null && result.user != null) {
        _token = result.token;
        _user = result.user;
        _error = null;

        // Store token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);

        // Set token for API calls
        ApiService.setAuthToken(_token);

        // Connect to WebSocket
        SocketService.instance.connect(_token!);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = result.error ?? 'Login failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = _toFriendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout
  Future<void> logout() async {
    try {
      await ApiService.logout();
    } catch (e) {
      // Ignore logout errors
    }
    await _clearAuth();
    notifyListeners();
  }

  /// Clear auth state
  Future<void> _clearAuth({String? errorMessage}) async {
    _token = null;
    _user = null;
    _error = errorMessage;

    ApiService.setAuthToken(null);
    SocketService.instance.disconnect();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
  }

  /// Clear error
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Refresh user data from server
  Future<void> refreshUser() async {
    if (_token == null) return;
    try {
      _user = await ApiService.getCurrentUser();
      notifyListeners();
    } catch (e) {
      // Ignore refresh errors
    }
  }

  void _setupAuthRevocationHandlers() {
    // WebSocket auth revoked (e.g. admin suspended account)
    SocketService.instance.onAuthRevoked = (payload) {
      final code = payload['code']?.toString();
      final message = payload['message']?.toString();

      if (code == 'ACCOUNT_SUSPENDED' || code == 'AUTH_SUSPENDED') {
        _forceLogout(message ?? 'Account is suspended');
        return;
      }

      _forceLogout(message ?? 'Session ended. Please log in again.');
    };

    // HTTP auth errors (expired token, suspended account)
    ApiService.onAuthError = (e) {
      if (e.code == 'ACCOUNT_SUSPENDED' || e.code == 'AUTH_SUSPENDED') {
        _forceLogout(e.message.isNotEmpty ? e.message : 'Account is suspended');
        return;
      }
      if (e.code == 'AUTH_INVALID') {
        _forceLogout('Session expired. Please log in again.');
        return;
      }
    };
  }

  Future<void> _forceLogout(String message) async {
    // Avoid extra work if we're already logged out.
    if (_token == null && _user == null) {
      _error = message;
      notifyListeners();
      return;
    }

    await _clearAuth(errorMessage: message);
    notifyListeners();
  }

  Future<bool> register(
      {required String username,
      required String email,
      required String password,
      required String fullName}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    _setupAuthRevocationHandlers();

    try {
      final result = await ApiService.register(
        username: username,
        email: email,
        password: password,
        fullName: fullName,
      );

      if (result.success && result.token != null && result.user != null) {
        _token = result.token;
        _user = result.user;
        _error = null;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', _token!);

        ApiService.setAuthToken(_token);
        SocketService.instance.connect(_token!);

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = result.error ?? 'Registration failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = _toFriendlyError(e);
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }
}
