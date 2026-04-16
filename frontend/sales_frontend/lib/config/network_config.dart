import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'platform_adapter.dart' as platform;

/// Resolves backend URLs for HTTP + Socket.IO.
///
/// Precedence (highest → lowest):
/// 1) Runtime OS env vars: `SGCO_API_BASE_URL` / `SGCO_WS_BASE_URL` (or `API_BASE_URL` / `WS_BASE_URL`)
/// 2) JSON config file (first match):
///    - `sgco_config.json` next to the executable
///    - `config.json` next to the executable
///    - `sgco_config.json` in current working directory
///    - `config.json` in current working directory
/// 3) Build-time dart-defines: `--dart-define=API_BASE_URL=...` / `--dart-define=WS_BASE_URL=...`
/// 4) Fallback defaults: localhost
class NetworkConfig {
  static const String _compileApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.45:3000/api',
  );
  static const String _compileWsBaseUrl = String.fromEnvironment(
    'WS_BASE_URL',
    defaultValue: 'http://192.168.1.45:3000',
  );

  static bool _initialized = false;
  static String _apiBaseUrl = _compileApiBaseUrl;
  static String _wsBaseUrl = _compileWsBaseUrl;
  static String _source = 'dart-define/default';

  static String get apiBaseUrl => _apiBaseUrl;
  static String get wsBaseUrl => _wsBaseUrl;
  static String get source => _source;

  static Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Start from compile-time values.
    _apply(_compileApiBaseUrl, _compileWsBaseUrl, 'dart-define/default');

    // Config file override.
    if (!kIsWeb) {
      final config = _loadConfigFromFile();
      if (config != null) {
        _apply(config.apiBaseUrl, config.wsBaseUrl, config.source);
      }
    }

    // Runtime env override (highest precedence).
    if (!kIsWeb) {
      final env = platform.platformEnvironment();
      final api = env['SGCO_API_BASE_URL'] ?? env['API_BASE_URL'];
      final ws = env['SGCO_WS_BASE_URL'] ?? env['WS_BASE_URL'];
      if ((api != null && api.trim().isNotEmpty) ||
          (ws != null && ws.trim().isNotEmpty)) {
        _apply(api, ws, 'env');
      }
    }

    debugPrint('[NetworkConfig] apiBaseUrl=$_apiBaseUrl (source=$_source)');
    debugPrint('[NetworkConfig] wsBaseUrl=$_wsBaseUrl (source=$_source)');
  }

  static void _apply(String? apiBaseUrl, String? wsBaseUrl, String source) {
    final api = (apiBaseUrl ?? _apiBaseUrl).trim();
    final ws = (wsBaseUrl ?? _wsBaseUrl).trim();

    _apiBaseUrl = _normalizeApiBaseUrl(api);
    _wsBaseUrl = _normalizeWsBaseUrl(ws, fallbackApi: _apiBaseUrl);
    _source = source;
  }

  static String _normalizeApiBaseUrl(String value) {
    var v = value.trim();
    if (v.isEmpty) return 'http://192.168.1.45:3000/api';

    // Remove trailing slashes.
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }

    // Ensure it ends with /api
    if (!v.toLowerCase().endsWith('/api')) {
      v = '$v/api';
    }
    return v;
  }

  static String _normalizeWsBaseUrl(String value,
      {required String fallbackApi}) {
    var v = value.trim();
    if (v.isEmpty) {
      // Derive from API base.
      v = fallbackApi;
    }

    // Remove trailing slashes.
    while (v.endsWith('/')) {
      v = v.substring(0, v.length - 1);
    }

    // If someone provided the API URL, strip the /api segment.
    if (v.toLowerCase().endsWith('/api')) {
      v = v.substring(0, v.length - 4);
    }

    return v;
  }

  static _FileConfig? _loadConfigFromFile() {
    final exeDir = platform.executableDirPath();

    final candidates = <String>[
      if (exeDir != null) '$exeDir\\sgco_config.json',
      if (exeDir != null) '$exeDir\\config.json',
      'sgco_config.json',
      'config.json',
    ];

    for (final p in candidates) {
      if (!platform.fileExists(p)) continue;
      final text = platform.readFileAsString(p);
      if (text == null) continue;

      try {
        final decoded = jsonDecode(text);
        if (decoded is! Map) continue;

        final map = Map<String, dynamic>.from(decoded as Map);

        // Accept multiple key styles.
        final api = (map['apiBaseUrl'] ?? map['API_BASE_URL'])?.toString();
        final ws = (map['wsBaseUrl'] ?? map['WS_BASE_URL'])?.toString();

        if ((api == null || api.trim().isEmpty) &&
            (ws == null || ws.trim().isEmpty)) {
          continue;
        }

        return _FileConfig(
          apiBaseUrl: api,
          wsBaseUrl: ws,
          source: 'file:$p',
        );
      } catch (_) {
        // Ignore invalid JSON.
        continue;
      }
    }

    return null;
  }
}

class _FileConfig {
  final String? apiBaseUrl;
  final String? wsBaseUrl;
  final String source;

  _FileConfig(
      {required this.apiBaseUrl,
      required this.wsBaseUrl,
      required this.source});
}
