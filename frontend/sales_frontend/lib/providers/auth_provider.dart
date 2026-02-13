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

  /// Initialize auth state from stored token
  Future<void> initialize() async {
    _isLoading = true;

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

    try {
      final result = await ApiService.login(username, password);

      if (result.success && result.token != null && result.user != null) {
        _token = result.token;
        _user = result.user;

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
      _error = e.toString();
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
  Future<void> _clearAuth() async {
    _token = null;
    _user = null;
    _error = null;

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
}
