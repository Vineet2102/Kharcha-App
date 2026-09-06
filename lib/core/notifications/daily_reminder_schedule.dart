/// Pure logic for deciding when the daily-logging-reminder notification
/// (spec §11.12) should next fire: today at [hour]:[minute] IST if that
/// time hasn't passed yet and nothing has been logged today, otherwise
/// tomorrow at the same time. A standalone function (not inlined into
/// `NotificationScheduler`) so it's unit-testable without Drift or a
/// platform channel, same precedent as `recurring_schedule.dart`.
///
/// [nowIst] must already be an IST wall-clock value (see
/// `AppTime.nowIst`/`AppTime.toIst` — UTC-flagged, but its `year`/`month`/
/// `day`/`hour`/`minute` fields are the IST digits). The result uses the
/// same convention: treat it as "IST, spelled using UTC fields", not a real
/// UTC instant.
DateTime nextDailyReminderFireIst({
  required DateTime nowIst,
  required bool loggedToday,
  required int hour,
  required int minute,
}) {
  final todayAt = DateTime.utc(
    nowIst.year,
    nowIst.month,
    nowIst.day,
    hour,
    minute,
  );
  if (!loggedToday && nowIst.isBefore(todayAt)) return todayAt;
  return todayAt.add(const Duration(days: 1));
}
