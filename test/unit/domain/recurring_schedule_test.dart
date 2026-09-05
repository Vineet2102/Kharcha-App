import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/domain/models/enums.dart';
import 'package:kharcha/domain/models/recurring_schedule.dart';

void main() {
  group('advanceDueDate', () {
    test('daily steps by intervalN days', () {
      expect(
        advanceDueDate(
          from: DateTime.utc(2026, 1, 1),
          frequency: RecurFrequency.daily,
          intervalN: 3,
        ),
        DateTime.utc(2026, 1, 4),
      );
    });

    test('weekly steps by intervalN weeks, preserving weekday', () {
      final from = DateTime.utc(2026, 1, 1); // a Thursday
      final next = advanceDueDate(
        from: from,
        frequency: RecurFrequency.weekly,
        intervalN: 2,
      );
      expect(next, DateTime.utc(2026, 1, 15));
      expect(next.weekday, from.weekday);
    });

    test('monthly on the 31st clamps to 28 Feb in a non-leap year', () {
      expect(
        advanceDueDate(
          from: DateTime.utc(2026, 1, 31),
          frequency: RecurFrequency.monthly,
          intervalN: 1,
          dayOfMonth: 31,
        ),
        DateTime.utc(2026, 2, 28),
      );
    });

    test('monthly on the 31st clamps to 29 Feb in a leap year', () {
      expect(
        advanceDueDate(
          from: DateTime.utc(2024, 1, 31),
          frequency: RecurFrequency.monthly,
          intervalN: 1,
          dayOfMonth: 31,
        ),
        DateTime.utc(2024, 2, 29),
      );
    });

    test('monthly falls back to from.day when dayOfMonth is null', () {
      expect(
        advanceDueDate(
          from: DateTime.utc(2026, 1, 15),
          frequency: RecurFrequency.monthly,
          intervalN: 1,
        ),
        DateTime.utc(2026, 2, 15),
      );
    });

    test('monthly with intervalN > 1 steps multiple months', () {
      expect(
        advanceDueDate(
          from: DateTime.utc(2026, 1, 31),
          frequency: RecurFrequency.monthly,
          intervalN: 2,
          dayOfMonth: 31,
        ),
        DateTime.utc(2026, 3, 31),
      );
    });

    test('monthly clamp only applies to the target month, not every month', () {
      // 31 Jan -> 28 Feb (clamped) -> 31 Mar (not stuck at 28 forever): each
      // step re-derives from dayOfMonth=31, not from the previous result's
      // clamped day.
      final feb = advanceDueDate(
        from: DateTime.utc(2026, 1, 31),
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        dayOfMonth: 31,
      );
      final mar = advanceDueDate(
        from: feb,
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        dayOfMonth: 31,
      );
      expect(feb, DateTime.utc(2026, 2, 28));
      expect(mar, DateTime.utc(2026, 3, 31));
    });

    test('yearly steps by intervalN years', () {
      expect(
        advanceDueDate(
          from: DateTime.utc(2026, 3, 15),
          frequency: RecurFrequency.yearly,
          intervalN: 1,
        ),
        DateTime.utc(2027, 3, 15),
      );
    });

    test(
      'yearly from 29 Feb in a leap year overflows to 1 Mar in a non-leap '
      'target year (mirrors the SQL function, which does not clamp here)',
      () {
        expect(
          advanceDueDate(
            from: DateTime.utc(2024, 2, 29),
            frequency: RecurFrequency.yearly,
            intervalN: 1,
          ),
          DateTime.utc(2025, 3, 1),
        );
      },
    );
  });

  group('dueOccurrencesFor', () {
    test('a single overdue occurrence', () {
      final result = dueOccurrencesFor(
        nextDueDate: DateTime.utc(2026, 1, 1),
        asOf: DateTime.utc(2026, 1, 5),
        frequency: RecurFrequency.monthly,
        intervalN: 1,
      );
      expect(result.occurrences, [DateTime.utc(2026, 1, 1)]);
      expect(result.nextDueDate, DateTime.utc(2026, 2, 1));
      expect(result.ruleExpired, isFalse);
    });

    test(
      'nothing due yet returns an empty list and leaves nextDueDate put',
      () {
        final result = dueOccurrencesFor(
          nextDueDate: DateTime.utc(2026, 2, 1),
          asOf: DateTime.utc(2026, 1, 5),
          frequency: RecurFrequency.monthly,
          intervalN: 1,
        );
        expect(result.occurrences, isEmpty);
        expect(result.nextDueDate, DateTime.utc(2026, 2, 1));
        expect(result.ruleExpired, isFalse);
      },
    );

    test('a rule dormant for 2 years posts at most 24 occurrences and stops '
        'cleanly, leaving nextDueDate still due for the next run', () {
      final result = dueOccurrencesFor(
        nextDueDate: DateTime.utc(2024, 1, 1),
        asOf: DateTime.utc(2026, 1, 1), // ~24 months later, daily-monthly
        frequency: RecurFrequency.monthly,
        intervalN: 1,
      );
      expect(result.occurrences, hasLength(24));
      expect(result.occurrences.first, DateTime.utc(2024, 1, 1));
      expect(result.occurrences.last, DateTime.utc(2025, 12, 1));
      expect(result.nextDueDate, DateTime.utc(2026, 1, 1));
      // Still due — the next run picks up where this one stopped.
      expect(result.nextDueDate.isAfter(DateTime.utc(2026, 1, 1)), isFalse);
    });

    test('stops at endDate and reports the rule as expired, when asOf reaches '
        'far enough to actually evaluate (and reject) the next occurrence', () {
      final result = dueOccurrencesFor(
        nextDueDate: DateTime.utc(2026, 1, 1),
        asOf: DateTime.utc(2026, 6, 1),
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        endDate: DateTime.utc(2026, 3, 1),
      );
      expect(result.occurrences, [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1), // the 3rd occurrence IS the end date
      ]);
      // asOf (June) reaches past Apr 1, the next would-be occurrence,
      // which is after endDate — so expiry is actually detected here.
      expect(result.ruleExpired, isTrue);
      expect(result.nextDueDate, DateTime.utc(2026, 4, 1));
    });

    test('does not detect expiry when asOf stops right at the last valid '
        'occurrence — nothing beyond endDate was ever evaluated', () {
      final result = dueOccurrencesFor(
        nextDueDate: DateTime.utc(2026, 1, 1),
        asOf: DateTime.utc(2026, 3, 1), // exactly the endDate
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        endDate: DateTime.utc(2026, 3, 1),
      );
      expect(result.occurrences, [
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 2, 1),
        DateTime.utc(2026, 3, 1),
      ]);
      expect(result.ruleExpired, isFalse);
      expect(result.nextDueDate, DateTime.utc(2026, 4, 1));
    });

    test('excludes an occurrence that would fall after endDate', () {
      final result = dueOccurrencesFor(
        nextDueDate: DateTime.utc(2026, 1, 15),
        asOf: DateTime.utc(2026, 6, 1),
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        endDate: DateTime.utc(2026, 1, 20),
      );
      expect(result.occurrences, [DateTime.utc(2026, 1, 15)]);
      expect(result.ruleExpired, isTrue);
      expect(result.nextDueDate, DateTime.utc(2026, 2, 15));
    });
  });

  group('previewOccurrences', () {
    test('returns the next `count` occurrences from `from`', () {
      final preview = previewOccurrences(
        from: DateTime.utc(2026, 10, 5),
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        count: 3,
      );
      expect(preview, [
        DateTime.utc(2026, 10, 5),
        DateTime.utc(2026, 11, 5),
        DateTime.utc(2026, 12, 5),
      ]);
    });

    test('stops early when endDate cuts the preview short', () {
      final preview = previewOccurrences(
        from: DateTime.utc(2026, 10, 5),
        frequency: RecurFrequency.monthly,
        intervalN: 1,
        endDate: DateTime.utc(2026, 11, 5),
        count: 3,
      );
      expect(preview, [DateTime.utc(2026, 10, 5), DateTime.utc(2026, 11, 5)]);
    });
  });
}
