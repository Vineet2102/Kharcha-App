import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/logging/app_logger.dart';

void main() {
  setUp(() => AppLogger.instance.clear());

  group('AppLogger', () {
    test('info/warn/error entries land in recentEntries', () {
      AppLogger.instance.info('info message');
      AppLogger.instance.warn('warn message');
      AppLogger.instance.error('error message');

      final levels = AppLogger.instance.recentEntries.map((e) => e.level);
      expect(levels, [LogLevel.info, LogLevel.warn, LogLevel.error]);
    });

    test('debug entries are recorded in a debug/test build (asserts run)', () {
      AppLogger.instance.debug('debug message');

      expect(AppLogger.instance.recentEntries, hasLength(1));
      expect(AppLogger.instance.recentEntries.single.level, LogLevel.debug);
    });

    test('warn/error carry the optional error and stack trace', () {
      final error = Exception('boom');
      final stackTrace = StackTrace.current;

      AppLogger.instance.warn('something went wrong', error, stackTrace);

      final entry = AppLogger.instance.recentEntries.single;
      expect(entry.error, error);
      expect(entry.stackTrace, stackTrace);
    });

    test('the ring buffer caps at 500 entries, dropping the oldest first', () {
      for (var i = 0; i < 510; i++) {
        AppLogger.instance.info('entry $i');
      }

      final entries = AppLogger.instance.recentEntries;
      expect(entries, hasLength(500));
      expect(entries.first.message, 'entry 10');
      expect(entries.last.message, 'entry 509');
    });

    test('clear() empties the buffer', () {
      AppLogger.instance.info('one');
      AppLogger.instance.clear();

      expect(AppLogger.instance.recentEntries, isEmpty);
    });

    test('exportAsText joins every entry on its own line', () {
      AppLogger.instance.info('first');
      AppLogger.instance.warn('second');

      final text = AppLogger.instance.exportAsText();

      expect(text.split('\n'), hasLength(2));
      expect(text, contains('INFO first'));
      expect(text, contains('WARN second'));
    });
  });

  group('LogEntry.toString', () {
    test('without an error, omits the trailing dash', () {
      final entry = LogEntry(
        LogLevel.info,
        'plain message',
        DateTime.utc(2026, 1, 1),
      );

      expect(entry.toString(), endsWith('INFO plain message'));
      expect(entry.toString(), isNot(contains('—')));
    });

    test('with an error, appends it after a dash', () {
      final entry = LogEntry(
        LogLevel.error,
        'oops',
        DateTime.utc(2026, 1, 1),
        error: 'boom',
      );

      expect(entry.toString(), contains('ERROR oops — boom'));
    });
  });
}
