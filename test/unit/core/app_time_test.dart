import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/time/app_time.dart';

void main() {
  group('AppTime.calendarDate', () {
    test('23:55 IST on the 30th stays on the 30th', () {
      // 23:55 IST = 18:25 UTC (IST is UTC+5:30).
      final instant = DateTime.utc(2026, 1, 30, 18, 25);
      expect(AppTime.calendarDate(instant), DateTime.utc(2026, 1, 30));
    });

    test('an instant just after IST midnight rolls to the next day', () {
      // 00:30 IST on 31 Jan = 19:00 UTC on 30 Jan — a naive UTC-date read
      // would wrongly say '30th'.
      final instant = DateTime.utc(2026, 1, 30, 19, 0);
      expect(AppTime.calendarDate(instant), DateTime.utc(2026, 1, 31));
    });

    test('matches the naive UTC date away from the boundary', () {
      final instant = DateTime.utc(2026, 6, 15, 10, 0);
      expect(AppTime.calendarDate(instant), DateTime.utc(2026, 6, 15));
    });
  });

  group('AppTime.monthStart / monthAfter', () {
    test('monthStart returns the 1st of the IST month', () {
      final instant = DateTime.utc(2026, 9, 20, 12, 0);
      expect(AppTime.monthStart(instant), DateTime.utc(2026, 9, 1));
    });

    test('monthAfter advances by N months, wrapping the year', () {
      final start = DateTime.utc(2026, 11, 1);
      expect(AppTime.monthAfter(start, 2), DateTime.utc(2027, 1, 1));
    });
  });

  group('AppTime.isSameIstMonth', () {
    test('true for two instants in the same IST month', () {
      final a = DateTime.utc(2026, 9, 1, 0, 0); // 05:30 IST, 1 Sep
      final b = DateTime.utc(2026, 9, 30, 17, 0); // 22:30 IST, 30 Sep
      expect(AppTime.isSameIstMonth(a, b), isTrue);
    });

    test('false across an IST month boundary hidden by the UTC date', () {
      final a = DateTime.utc(2026, 9, 30, 18, 0); // 23:30 IST, still Sep
      final b = DateTime.utc(2026, 9, 30, 19, 0); // 00:30 IST, now Oct
      expect(AppTime.isSameIstMonth(a, b), isFalse);
    });
  });

  group('AppTime.parseDateOnly', () {
    test('parses a bare date string as UTC midnight, not local midnight', () {
      // A naive `DateTime.parse('2026-09-01')` returns a *local*-flagged
      // DateTime; on a device physically in IST that instant is actually
      // 2026-08-31T18:30:00Z. parseDateOnly must not leak the host's
      // timezone into the result.
      expect(AppTime.parseDateOnly('2026-09-01'), DateTime.utc(2026, 9, 1));
    });

    test('discards a time-of-day component if present', () {
      expect(
        AppTime.parseDateOnly('2026-09-01T00:00:00.000Z'),
        DateTime.utc(2026, 9, 1),
      );
    });

    test('parseDateOnlyOrNull passes through null', () {
      expect(AppTime.parseDateOnlyOrNull(null), isNull);
    });

    test('parseDateOnlyOrNull parses a non-null value', () {
      expect(
        AppTime.parseDateOnlyOrNull('2026-09-01'),
        DateTime.utc(2026, 9, 1),
      );
    });
  });

  group('AppTime.daysInMonth', () {
    test('30-day month', () {
      expect(AppTime.daysInMonth(DateTime.utc(2026, 9, 1)), 30);
    });

    test('31-day month', () {
      expect(AppTime.daysInMonth(DateTime.utc(2026, 1, 1)), 31);
    });

    test('February in a leap year', () {
      expect(AppTime.daysInMonth(DateTime.utc(2028, 2, 1)), 29);
    });

    test('February in a non-leap year', () {
      expect(AppTime.daysInMonth(DateTime.utc(2026, 2, 1)), 28);
    });
  });

  group('AppTime month labels', () {
    test('monthLabel formats the full month name and year', () {
      expect(AppTime.monthLabel(DateTime.utc(2026, 9, 1)), 'September 2026');
    });

    test('monthLabelShort formats the abbreviated month name and year', () {
      expect(AppTime.monthLabelShort(DateTime.utc(2026, 9, 1)), 'Sep 2026');
    });
  });
}
