// Stub (non-IO platforms, e.g. web) for reading environment/config.

Map<String, String> platformEnvironment() => const {};

String? executableDirPath() => null;

bool fileExists(String path) => false;

String? readFileAsString(String path) => null;
