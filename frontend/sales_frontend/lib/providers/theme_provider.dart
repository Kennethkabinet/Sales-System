import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  static const String _themeModeKey = 'app_theme_mode';

  ThemeMode _themeMode = ThemeMode.light;
  bool _isSwitchingTheme = false;
  int _themeSwitchSeq = 0;

    static const Duration _minThemeSwitchOverlayDuration =
      Duration(milliseconds: 700);

  ThemeProvider() {
    _loadThemeMode();
  }

  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  bool get isSwitchingTheme => _isSwitchingTheme;

  Future<void> toggleTheme() async {
    await setThemeMode(
      isDarkMode ? ThemeMode.light : ThemeMode.dark,
      showLoadingOverlay: true,
    );
  }

  Future<void> setThemeMode(
    ThemeMode mode, {
    bool showLoadingOverlay = false,
  }) async {
    if (_themeMode == mode) return;

    final seq = ++_themeSwitchSeq;
    final start = DateTime.now();

    if (showLoadingOverlay) {
      _isSwitchingTheme = true;
      notifyListeners();

      // Give Flutter a frame to paint the overlay before the theme rebuild.
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (seq != _themeSwitchSeq) return;
    }

    _themeMode = mode;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeModeKey, _themeMode.name);

    if (showLoadingOverlay && seq == _themeSwitchSeq) {
      final elapsed = DateTime.now().difference(start);
      final remaining = _minThemeSwitchOverlayDuration - elapsed;
      if (!remaining.isNegative) {
        await Future.delayed(remaining);
      }

      if (seq == _themeSwitchSeq) {
        _isSwitchingTheme = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString(_themeModeKey);

    if (savedMode == ThemeMode.dark.name) {
      _themeMode = ThemeMode.dark;
      notifyListeners();
      return;
    }

    if (savedMode == ThemeMode.light.name) {
      _themeMode = ThemeMode.light;
      notifyListeners();
    }
  }
}
