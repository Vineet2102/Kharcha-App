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
