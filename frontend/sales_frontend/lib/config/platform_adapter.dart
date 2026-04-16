// Conditional imports so we can compile on web without dart:io.

import 'platform_adapter_stub.dart'
    if (dart.library.io) 'platform_adapter_io.dart' as impl;

Map<String, String> platformEnvironment() => impl.platformEnvironment();

String? executableDirPath() => impl.executableDirPath();

bool fileExists(String path) => impl.fileExists(path);

String? readFileAsString(String path) => impl.readFileAsString(path);
