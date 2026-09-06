import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/money/money.dart';
import '../../core/notifications/daily_reminder_schedule.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/notifications/notification_settings.dart';
import '../../core/time/app_time.dart';
import '../../routing/routes.dart';

part 'notification_scheduler.g.dart';

/// Fixed, stable notification ids — one per logical notification "slot", so
/// re-arming a type replaces its own earlier notification/alarm rather than
/// stacking a new one. Chosen well clear of `BudgetAlertService`'s
/// `budget.id.hashCode & 0x7fffffff` range in practice, though a collision
/// there would be harmless anyway (two different Android channels).
const _dailyReminderId = 900001;
const _monthlySummaryId = 900002;
const _recurringDueId = 900003;
const _syncStuckId = 900004;

/// Re-evaluates and re-arms every notification type from spec §11.12's
/// table except budget alerts (T-8.5's `BudgetAlertService`, unchanged).
/// Called on every app start and every resume (T-13.2's "must be
/// re-scheduled on every app start").
///
/// Only the **daily reminder** is a true OS-scheduled alarm
/// (`NotificationService.scheduleAt`, backed by `zonedSchedule`) — its
/// "skip if already logged today" condition is knowable at
/// schedule-time, and logging an expense always happens with the app in
/// the foreground, which re-triggers this same re-evaluation and cancels
/// the now-redundant alarm. The other three (monthly summary, recurring
/// due, sync stuck) all need content that can only be computed live
/// ("family spent ₹X", "N items waiting", "outbox stuck") — there's no way
/// to bake that into a notification scheduled ahead of time, so they're
/// evaluated and, if due, shown immediately instead, each deduplicated in
/// `shared_preferences` so a later resume doesn't re-fire the same one.
class NotificationScheduler {
  NotificationScheduler(this._db, this._notifications);

  final AppDatabase _db;
  final NotificationService _notifications;

  Future<void> runAll(String householdId) async {
    final prefs = await SharedPreferences.getInstance();
    final settings = prefs.loadNotificationSettings();
    await _scheduleDailyReminder(householdId, settings);
    await _evaluateMonthlySummary(householdId, prefs, settings);
    await _evaluateRecurringDue(householdId, prefs, settings);
    await _evaluateSyncStuck(prefs, settings);
  }

  Future<void> _scheduleDailyReminder(
    String householdId,
    NotificationSettings settings,
  ) async {
    await _notifications.cancel(_dailyReminderId);
    if (!settings.dailyReminderEnabled) return;

    final today = AppTime.calendarDate(DateTime.now().toUtc());
    final loggedToday = await _db.expenseDao.hasAnyOn(householdId, today);
    final targetIst = nextDailyReminderFireIst(
      nowIst: AppTime.nowIst(),
      loggedToday: loggedToday,
      hour: settings.dailyReminderHour,
      minute: settings.dailyReminderMinute,
    );

    await _notifications.scheduleAt(
      id: _dailyReminderId,
      title: 'Daily reminder',
      body: "You haven't logged any expenses today.",
      scheduledDate: tz.TZDateTime(
        tz.local,
        targetIst.year,
        targetIst.month,
        targetIst.day,
        targetIst.hour,
        targetIst.minute,
      ),
      channelId: 'daily_reminder',
      channelName: 'Daily reminder',
      channelDescription: 'A daily reminder to log today\'s expenses',
      payload: AppRoutes.expenseNew,
    );
  }

  /// Fires once per calendar month, the first time the app is opened on or
  /// after the 1st — spec §11.12 nominally schedules this for "1st of each
  /// month, 10:00 IST", but the body needs the month that JUST ended
  /// totals, which don't exist yet at any earlier scheduling time. See the
  /// class doc for why this is evaluated live instead of pre-scheduled.
  Future<void> _evaluateMonthlySummary(
    String householdId,
    SharedPreferences prefs,
    NotificationSettings settings,
  ) async {
    if (!settings.monthlySummaryEnabled) return;
    final currentMonthStart = AppTime.monthStart(DateTime.now().toUtc());
    final previousMonthStart = AppTime.monthAfter(currentMonthStart, -1);
    final key = 'notif_monthly_summary_notified_${_yyyyMM(previousMonthStart)}';
    if (prefs.getBool(key) == true) return;

    final expensePaise = await _db.reportDao
        .watchExpenseTotal(
          householdId: householdId,
          start: previousMonthStart,
          end: currentMonthStart,
        )
        .first;
    final incomePaise = await _db.reportDao
        .watchIncomeTotal(
          householdId: householdId,
          start: previousMonthStart,
          end: currentMonthStart,
        )
        .first;
    final monthName = AppTime.monthLabel(previousMonthStart).split(' ').first;

    await _notifications.show(
      id: _monthlySummaryId,
      title: 'Monthly summary',
      body:
          '$monthName: family spent ${Money(expensePaise).format()}, '
          'saved ${Money(incomePaise - expensePaise).format()}',
      channelId: 'monthly_summary',
      channelName: 'Monthly summary',
      channelDescription: "Last month's household spend/income summary",
      payload: AppRoutes.analytics,
    );
    await prefs.setBool(key, true);
  }

  /// Fires at most once per day — "N recurring items are waiting for
  /// confirmation" (spec §11.12), counting only active, currently-due,
  /// non-auto-post rules (`RecurringDao.dueOn`, same filter the Dashboard's
  /// pending-recurring card and the posting engine already use).
  Future<void> _evaluateRecurringDue(
    String householdId,
    SharedPreferences prefs,
    NotificationSettings settings,
  ) async {
    if (!settings.recurringDueEnabled) return;
    final today = AppTime.calendarDate(DateTime.now().toUtc());
    final key = 'notif_recurring_due_notified_${_yyyyMMdd(today)}';
    if (prefs.getBool(key) == true) return;

    final dueRules = await _db.recurringDao.dueOn(householdId, today);
    final pendingCount = dueRules.where((r) => !r.autoPost).length;
    if (pendingCount == 0) return;

    await _notifications.show(
      id: _recurringDueId,
      title: 'Recurring items due',
      body: pendingCount == 1
          ? '1 recurring item is waiting for confirmation'
          : '$pendingCount recurring items are waiting for confirmation',
      channelId: 'recurring_due',
      channelName: 'Recurring due',
      channelDescription: 'Recurring bills/income waiting for confirmation',
      payload: AppRoutes.dashboard,
    );
    await prefs.setBool(key, true);
  }

  /// Fires at most once every 24h while the outbox has an entry older than
  /// 24h (spec §11.12) — re-checked, not a one-shot latch, so a sync issue
  /// that drags on keeps the user informed without spamming every resume.
  Future<void> _evaluateSyncStuck(
    SharedPreferences prefs,
    NotificationSettings settings,
  ) async {
    if (!settings.syncStuckEnabled) return;
    final oldest = await _db.outboxDao.oldestPendingCreatedAt();
    if (oldest == null) return;
    final now = DateTime.now().toUtc();
    if (now.difference(oldest.toUtc()) < const Duration(hours: 24)) return;

    const key = 'notif_sync_stuck_last_notified_ms';
    final lastMs = prefs.getInt(key);
    if (lastMs != null) {
      final last = DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true);
      if (now.difference(last) < const Duration(hours: 24)) return;
    }

    await _notifications.show(
      id: _syncStuckId,
      title: 'Sync issue',
      body: "Some expenses haven't synced. Open the app on Wi-Fi.",
      channelId: 'sync_stuck',
      channelName: 'Sync issues',
      channelDescription: 'Warns when changes have been waiting to sync for a while',
      payload: AppRoutes.diagnostics,
    );
    await prefs.setInt(key, now.millisecondsSinceEpoch);
  }

  static String _yyyyMM(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}${d.month.toString().padLeft(2, '0')}';

  static String _yyyyMMdd(DateTime d) =>
      '${_yyyyMM(d)}${d.day.toString().padLeft(2, '0')}';
}

@Riverpod(keepAlive: true)
NotificationScheduler notificationScheduler(Ref ref) => NotificationScheduler(
  ref.watch(appDatabaseProvider),
  NotificationService.instance,
);
