import 'dart:developer' as dev;

/// App-wide logger. Use this instead of `print` (AGENTS.md §6).
abstract final class AppLogger {
  static void info(String message) => dev.log(message, name: 'asani');
  static void warn(String message) => dev.log(message, name: 'asani', level: 900);
  static void error(String message, [Object? error, StackTrace? stack]) =>
      dev.log(message, name: 'asani', level: 1000, error: error, stackTrace: stack);
}
