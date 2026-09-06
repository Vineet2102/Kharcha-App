import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/notifications/daily_reminder_schedule.dart';

void main() {
  group('nextDailyReminderFireIst', () {
    test('not logged yet, reminder time still ahead today → fires today', () {
      final result = nextDailyReminderFireIst(
        nowIst: DateTime.utc(2026, 9, 6, 14, 0),
        loggedToday: false,
        hour: 21,
        minute: 0,
      );
      expect(result, DateTime.utc(2026, 9, 6, 21, 0));
    });

    test('not logged yet, but reminder time already passed today → tomorrow', () {
      final result = nextDailyReminderFireIst(
        nowIst: DateTime.utc(2026, 9, 6, 22, 0),
        loggedToday: false,
        hour: 21,
        minute: 0,
      );
      expect(result, DateTime.utc(2026, 9, 7, 21, 0));
    });

    test('already logged today, reminder time still ahead → skips to tomorrow', () {
      final result = nextDailyReminderFireIst(
        nowIst: DateTime.utc(2026, 9, 6, 14, 0),
        loggedToday: true,
        hour: 21,
        minute: 0,
      );
      expect(result, DateTime.utc(2026, 9, 7, 21, 0));
    });

    test('already logged today, reminder time already passed → tomorrow', () {
      final result = nextDailyReminderFireIst(
        nowIst: DateTime.utc(2026, 9, 6, 22, 0),
        loggedToday: true,
        hour: 21,
        minute: 0,
      );
      expect(result, DateTime.utc(2026, 9, 7, 21, 0));
    });

    test('exactly at the reminder minute counts as already passed', () {
      final result = nextDailyReminderFireIst(
        nowIst: DateTime.utc(2026, 9, 6, 21, 0),
        loggedToday: false,
        hour: 21,
        minute: 0,
      );
      expect(result, DateTime.utc(2026, 9, 7, 21, 0));
    });

    test('respects a custom reminder time', () {
      final result = nextDailyReminderFireIst(
        nowIst: DateTime.utc(2026, 9, 6, 6, 0),
        loggedToday: false,
        hour: 7,
        minute: 30,
      );
      expect(result, DateTime.utc(2026, 9, 6, 7, 30));
    });
  });
}
