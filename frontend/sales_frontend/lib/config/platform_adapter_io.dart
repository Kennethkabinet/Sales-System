// IO implementation for desktop/mobile builds.

import 'dart:io';

Map<String, String> platformEnvironment() => Platform.environment;

String? executableDirPath() {
  try {
    // On Flutter desktop, this is the path to the app executable.
    final exe = File(Platform.resolvedExecutable);
    return exe.parent.path;
  } catch (_) {
    return null;
  }
}

bool fileExists(String path) {
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

String? readFileAsString(String path) {
  try {
    return File(path).readAsStringSync();
  } catch (_) {
    return null;
  }
}
