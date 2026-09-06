import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/notifications/notification_settings.dart';
import '../../../data/repositories/notification_scheduler.dart';

part 'notification_settings_controller.g.dart';

/// Backs the Notifications settings screen (spec §11.12/§11.13). Loads once
/// from `shared_preferences` — the constructor-time defaults are shown
/// until that resolves, same precedent as every other prefs-backed
/// controller in this app, and imperceptible in practice. Every setter
/// persists immediately, updates [state], then re-runs
/// [NotificationScheduler] so a toggle or a new reminder time takes effect
/// right away rather than waiting for the next app start.
@Riverpod(keepAlive: true)
class NotificationSettingsController extends _$NotificationSettingsController {
  @override
  NotificationSettings build() {
    _load();
    return const NotificationSettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.loadNotificationSettings();
  }

  Future<void> _apply(
    Future<void> Function(SharedPreferences prefs) write,
    NotificationSettings Function(NotificationSettings current) update,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await write(prefs);
    state = update(state);
    await ref
        .read(notificationSchedulerProvider)
        .runAll(AppConstants.seedHouseholdId);
  }

  Future<void> setDailyReminderEnabled(bool value) => _apply(
    (prefs) =>
        prefs.setBool(NotificationSettingsKeys.dailyReminderEnabled, value),
    (s) => s.copyWith(dailyReminderEnabled: value),
  );

  Future<void> setDailyReminderTime(int hour, int minute) => _apply((
    prefs,
  ) async {
    await prefs.setInt(NotificationSettingsKeys.dailyReminderHour, hour);
    await prefs.setInt(NotificationSettingsKeys.dailyReminderMinute, minute);
  }, (s) => s.copyWith(dailyReminderHour: hour, dailyReminderMinute: minute));

  Future<void> setBudgetAlertsEnabled(bool value) => _apply(
    (prefs) =>
        prefs.setBool(NotificationSettingsKeys.budgetAlertsEnabled, value),
    (s) => s.copyWith(budgetAlertsEnabled: value),
  );

  Future<void> setMonthlySummaryEnabled(bool value) => _apply(
    (prefs) =>
        prefs.setBool(NotificationSettingsKeys.monthlySummaryEnabled, value),
    (s) => s.copyWith(monthlySummaryEnabled: value),
  );

  Future<void> setRecurringDueEnabled(bool value) => _apply(
    (prefs) =>
        prefs.setBool(NotificationSettingsKeys.recurringDueEnabled, value),
    (s) => s.copyWith(recurringDueEnabled: value),
  );

  Future<void> setSyncStuckEnabled(bool value) => _apply(
    (prefs) => prefs.setBool(NotificationSettingsKeys.syncStuckEnabled, value),
    (s) => s.copyWith(syncStuckEnabled: value),
  );
}
