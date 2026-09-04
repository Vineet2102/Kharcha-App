import 'dart:collection';
import 'dart:developer' as developer;

enum LogLevel { debug, info, warn, error }

class LogEntry {
  LogEntry(this.level, this.message, this.timestamp, {this.error, this.stackTrace});

  final LogLevel level;
  final String message;
  final DateTime timestamp;
  final Object? error;
  final StackTrace? stackTrace;

  @override
  String toString() {
    final prefix = '${timestamp.toIso8601String()} ${level.name.toUpperCase()}';
    return error == null ? '$prefix $message' : '$prefix $message — $error';
  }
}

/// Wraps `dart:developer` log() and keeps an in-memory ring buffer of the
/// last 500 entries for the Diagnostics screen (spec §9.8, T-14.5) — the
/// debugging lifeline for phones that aren't in your hand.
class AppLogger {
  AppLogger._();

  static final AppLogger instance = AppLogger._();

  static const _maxEntries = 500;
  final Queue<LogEntry> _buffer = Queue<LogEntry>();

  List<LogEntry> get recentEntries => List.unmodifiable(_buffer);

  /// Compiled out of release builds — `assert` bodies are stripped there.
  void debug(String message) {
    assert(() {
      _log(LogLevel.debug, message);
      return true;
    }());
  }

  void info(String message) => _log(LogLevel.info, message);

  void warn(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.warn, message, error, stackTrace);

  void error(String message, [Object? error, StackTrace? stackTrace]) =>
      _log(LogLevel.error, message, error, stackTrace);

  void _log(LogLevel level, String message, [Object? error, StackTrace? stackTrace]) {
    final entry = LogEntry(level, message, DateTime.now(), error: error, stackTrace: stackTrace);
    _buffer.addLast(entry);
    while (_buffer.length > _maxEntries) {
      _buffer.removeFirst();
    }
    developer.log(
      message,
      name: 'kharcha',
      level: _levelValue(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _levelValue(LogLevel level) => switch (level) {
        LogLevel.debug => 500,
        LogLevel.info => 800,
        LogLevel.warn => 900,
        LogLevel.error => 1000,
      };

  String exportAsText() => _buffer.map((e) => e.toString()).join('\n');

  void clear() => _buffer.clear();
}
