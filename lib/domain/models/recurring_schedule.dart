import 'enums.dart';

// Pure recurrence-scheduling logic (spec §11.8, T-9.1/T-9.2/T-9.3). Not a
// synced entity — like BudgetStatus, this has no JSON codec. Every DateTime
// here is a date-only UTC marker (as produced by
// `AppTime.calendarDate`/`parseDateOnly`); never pass one carrying a
// time-of-day.

/// Mirrors the Postgres `advance_due_date()` function (spec §6.6) exactly:
/// `daily`/`weekly`/`yearly` just add the interval; `monthly` steps by whole
/// months from [from]'s month-start (so there's no day-of-month to overflow
/// mid-calculation) and then clamps the target day to the last valid day of
/// the resulting month — e.g. the 31st clamps to the 28th/29th in February.
///
/// The SQL function also accepts a `p_weekday` parameter, but no branch of
/// it actually uses that value (weekly recurrence just steps by whole weeks
/// from [from], which already preserves the weekday) — that dead parameter
/// isn't mirrored here.
DateTime advanceDueDate({
  required DateTime from,
  required RecurFrequency frequency,
  required int intervalN,
  int? dayOfMonth,
}) {
  switch (frequency) {
    case RecurFrequency.daily:
      return from.add(Duration(days: intervalN));
    case RecurFrequency.weekly:
      return from.add(Duration(days: 7 * intervalN));
    case RecurFrequency.monthly:
      final monthStart = DateTime.utc(from.year, from.month + intervalN, 1);
      final lastDayOfMonth = DateTime.utc(
        monthStart.year,
        monthStart.month + 1,
        0,
      ).day;
      final targetDay = (dayOfMonth ?? from.day).clamp(1, lastDayOfMonth);
      return DateTime.utc(monthStart.year, monthStart.month, targetDay);
    case RecurFrequency.yearly:
      // Deliberately unclamped, mirroring the SQL function's own `p_from +
      // interval 'N years'` (no month-end handling in that branch): 29 Feb
      // in a leap year rolls over to 1 Mar when the target year isn't leap
      // — `DateTime.utc` overflows the same way Postgres's date+interval
      // arithmetic does, so the two stay in agreement.
      return DateTime.utc(from.year + intervalN, from.month, from.day);
  }
}

/// The result of catching a rule up to [DueOccurrences.nextDueDate]: every
/// occurrence date from the rule's old `next_due_date` through [asOf]
/// (spec §11.8's posting-engine loop), capped at `maxOccurrences` per call
/// (T-9.3's 24-occurrence catch-up cap), plus whether the rule ran off the
/// end of its [DateTime] end date partway through (`ruleExpired`) — the
/// caller should deactivate the rule in that case.
class DueOccurrences {
  const DueOccurrences({
    required this.occurrences,
    required this.nextDueDate,
    required this.ruleExpired,
  });

  final List<DateTime> occurrences;
  final DateTime nextDueDate;
  final bool ruleExpired;
}

/// Pure catch-up computation for one rule (spec §11.8's posting-engine
/// loop): every occurrence at or before [asOf], starting from
/// [nextDueDate] and stepping via [advanceDueDate], stopping at whichever
/// comes first of [asOf], [endDate], or [maxOccurrences] occurrences.
DueOccurrences dueOccurrencesFor({
  required DateTime nextDueDate,
  required DateTime asOf,
  required RecurFrequency frequency,
  required int intervalN,
  int? dayOfMonth,
  DateTime? endDate,
  int maxOccurrences = 24,
}) {
  final occurrences = <DateTime>[];
  var due = nextDueDate;
  var expired = false;
  while (occurrences.length < maxOccurrences && !due.isAfter(asOf)) {
    if (endDate != null && due.isAfter(endDate)) {
      expired = true;
      break;
    }
    occurrences.add(due);
    due = advanceDueDate(
      from: due,
      frequency: frequency,
      intervalN: intervalN,
      dayOfMonth: dayOfMonth,
    );
  }
  return DueOccurrences(
    occurrences: occurrences,
    nextDueDate: due,
    ruleExpired: expired,
  );
}

/// The rule editor's live preview (spec §11.8: "Next 3 occurrences: 5 Oct,
/// 5 Nov, 5 Dec") — the next [count] occurrences starting at [from] (the
/// rule's `start_date` for a new rule, or its current `next_due_date` when
/// editing one), stopping early if [endDate] is reached.
List<DateTime> previewOccurrences({
  required DateTime from,
  required RecurFrequency frequency,
  required int intervalN,
  int? dayOfMonth,
  DateTime? endDate,
  int count = 3,
}) {
  final result = <DateTime>[];
  var due = from;
  while (result.length < count) {
    if (endDate != null && due.isAfter(endDate)) break;
    result.add(due);
    due = advanceDueDate(
      from: due,
      frequency: frequency,
      intervalN: intervalN,
      dayOfMonth: dayOfMonth,
    );
  }
  return result;
}
