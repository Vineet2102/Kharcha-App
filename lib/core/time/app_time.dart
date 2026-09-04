/// IST (Asia/Kolkata, UTC+5:30, no DST) helpers. Every timestamp in this app
/// is stored as UTC (`timestamptz`); the app always converts to IST before
/// deriving a calendar date or a display label (spec §6.1, §9.2).
///
/// This mirrors the DB trigger `public.set_ist_date()` in
/// `0005_functions_triggers.sql` exactly, so the client and server never
/// disagree about which calendar day an expense falls on.
class AppTime {
  const AppTime._();

  static const istOffset = Duration(hours: 5, minutes: 30);

  /// The current instant, in IST wall-clock time.
  static DateTime nowIst() => toIst(DateTime.now().toUtc());

  /// Converts any [instant] (local or UTC) to its IST wall-clock equivalent.
  /// The result is returned with `isUtc == true` so date-only comparisons
  /// are stable regardless of the host device's own timezone — treat the
  /// returned value as "IST, spelled using UTC fields", never convert it
  /// back with `.toLocal()`.
  static DateTime toIst(DateTime instant) => instant.toUtc().add(istOffset);

  /// The IST calendar date (midnight, no time-of-day) for [instant].
  static DateTime calendarDate(DateTime instant) {
    final ist = toIst(instant);
    return DateTime.utc(ist.year, ist.month, ist.day);
  }

  /// The first day (IST) of the month containing [instant].
  static DateTime monthStart(DateTime instant) {
    final ist = toIst(instant);
    return DateTime.utc(ist.year, ist.month, 1);
  }

  /// The first day (IST) of the month [count] months after [periodMonth].
  /// [periodMonth] must already be a month-start value (e.g. from
  /// [monthStart]).
  static DateTime monthAfter(DateTime periodMonth, int count) =>
      DateTime.utc(periodMonth.year, periodMonth.month + count, 1);

  static bool isSameIstMonth(DateTime a, DateTime b) {
    final istA = toIst(a);
    final istB = toIst(b);
    return istA.year == istB.year && istA.month == istB.month;
  }

  /// True when [periodMonth] is strictly after the current IST month —
  /// used to stop the dashboard's month selector at "now".
  static bool isFutureMonth(DateTime periodMonth) {
    final currentMonthStart = monthStart(DateTime.now().toUtc());
    return periodMonth.isAfter(currentMonthStart);
  }

  /// Parses a bare `date`-typed Postgres column value (e.g. `"2026-09-01"`,
  /// no time-of-day or timezone suffix) as a UTC calendar-date marker.
  ///
  /// `DateTime.parse` on a string with no offset returns a **local**-flagged
  /// DateTime — on any device not physically in UTC (every Kharcha device,
  /// by design, is in IST, per spec §3), that silently shifts the instant
  /// by the device's UTC offset once `millisecondsSinceEpoch` is taken (as
  /// Drift does for storage). This mirrors the `DateTime.utc(y, m, d)`
  /// convention every calendar-date column (`spent_on`, `received_on`,
  /// `period_month`, `start_date`/`end_date`/`next_due_date`/
  /// `last_posted_on`) already uses on write — every domain model's
  /// `fromJson` for one of those columns must route through this, not a
  /// bare `DateTime.parse`.
  static DateTime parseDateOnly(String value) {
    final parsed = DateTime.parse(value);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  /// Nullable sibling of [parseDateOnly], for optional `date` columns
  /// (`end_date`, `last_posted_on`).
  static DateTime? parseDateOnlyOrNull(String? value) =>
      value == null ? null : parseDateOnly(value);

  /// Number of days in the month [periodMonth] falls in.
  static int daysInMonth(DateTime periodMonth) =>
      DateTime.utc(periodMonth.year, periodMonth.month + 1, 0).day;

  /// Days left (inclusive of today) in [periodMonth], in IST. 0 for a past
  /// month, the full day count for a future month — used for a budget's
  /// "daily allowance" (spec §11.7); callers only ever pass the current or a
  /// past/future month, never a mid-month instant.
  static int daysRemainingInMonth(DateTime periodMonth) {
    final today = nowIst();
    if (!isSameIstMonth(periodMonth, today)) {
      return periodMonth.isAfter(today) ? daysInMonth(periodMonth) : 0;
    }
    return daysInMonth(periodMonth) - today.day + 1;
  }

  static const _monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  /// e.g. 'September 2026'.
  static String monthLabel(DateTime periodMonth) =>
      '${_monthNames[periodMonth.month - 1]} ${periodMonth.year}';

  /// e.g. 'Sep 2026'.
  static String monthLabelShort(DateTime periodMonth) =>
      '${_monthNames[periodMonth.month - 1].substring(0, 3)} ${periodMonth.year}';
}
