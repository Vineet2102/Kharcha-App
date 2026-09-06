import 'package:shared_preferences/shared_preferences.dart';

/// Per-type on/off switches + the daily reminder's time-of-day (spec
/// §11.12: "Every notification type has an on/off switch in Settings,
/// persisted in shared_preferences"). All default enabled; the daily
/// reminder defaults to 21:00 IST per §11.12's schedule table. Budget
/// warning and budget exceeded (two rows in that table) share one toggle
/// here — both are the same threshold-crossing feature (`BudgetAlertService`,
/// T-8.5), not two independently firing notification types.
class NotificationSettings {
  const NotificationSettings({
    this.dailyReminderEnabled = true,
    this.dailyReminderHour = 21,
    this.dailyReminderMinute = 0,
    this.budgetAlertsEnabled = true,
    this.monthlySummaryEnabled = true,
    this.recurringDueEnabled = true,
    this.syncStuckEnabled = true,
  });

  final bool dailyReminderEnabled;
  final int dailyReminderHour;
  final int dailyReminderMinute;
  final bool budgetAlertsEnabled;
  final bool monthlySummaryEnabled;
  final bool recurringDueEnabled;
  final bool syncStuckEnabled;

  NotificationSettings copyWith({
    bool? dailyReminderEnabled,
    int? dailyReminderHour,
    int? dailyReminderMinute,
    bool? budgetAlertsEnabled,
    bool? monthlySummaryEnabled,
    bool? recurringDueEnabled,
    bool? syncStuckEnabled,
  }) => NotificationSettings(
    dailyReminderEnabled: dailyReminderEnabled ?? this.dailyReminderEnabled,
    dailyReminderHour: dailyReminderHour ?? this.dailyReminderHour,
    dailyReminderMinute: dailyReminderMinute ?? this.dailyReminderMinute,
    budgetAlertsEnabled: budgetAlertsEnabled ?? this.budgetAlertsEnabled,
    monthlySummaryEnabled: monthlySummaryEnabled ?? this.monthlySummaryEnabled,
    recurringDueEnabled: recurringDueEnabled ?? this.recurringDueEnabled,
    syncStuckEnabled: syncStuckEnabled ?? this.syncStuckEnabled,
  );
}

/// `shared_preferences` keys for [NotificationSettings] — kept alongside the
/// model so `NotificationScheduler` (which reads a `SharedPreferences`
/// instance directly, not through the Riverpod settings controller) and the
/// Settings screen's controller can never drift onto two different key
/// spellings.
class NotificationSettingsKeys {
  const NotificationSettingsKeys._();

  static const dailyReminderEnabled = 'notif_daily_reminder_enabled';
  static const dailyReminderHour = 'notif_daily_reminder_hour';
  static const dailyReminderMinute = 'notif_daily_reminder_minute';
  static const budgetAlertsEnabled = 'notif_budget_alerts_enabled';
  static const monthlySummaryEnabled = 'notif_monthly_summary_enabled';
  static const recurringDueEnabled = 'notif_recurring_due_enabled';
  static const syncStuckEnabled = 'notif_sync_stuck_enabled';
}

extension NotificationSettingsPrefs on SharedPreferences {
  NotificationSettings loadNotificationSettings() {
    const d = NotificationSettings();
    return NotificationSettings(
      dailyReminderEnabled:
          getBool(NotificationSettingsKeys.dailyReminderEnabled) ??
          d.dailyReminderEnabled,
      dailyReminderHour:
          getInt(NotificationSettingsKeys.dailyReminderHour) ??
          d.dailyReminderHour,
      dailyReminderMinute:
          getInt(NotificationSettingsKeys.dailyReminderMinute) ??
          d.dailyReminderMinute,
      budgetAlertsEnabled:
          getBool(NotificationSettingsKeys.budgetAlertsEnabled) ??
          d.budgetAlertsEnabled,
      monthlySummaryEnabled:
          getBool(NotificationSettingsKeys.monthlySummaryEnabled) ??
          d.monthlySummaryEnabled,
      recurringDueEnabled:
          getBool(NotificationSettingsKeys.recurringDueEnabled) ??
          d.recurringDueEnabled,
      syncStuckEnabled:
          getBool(NotificationSettingsKeys.syncStuckEnabled) ??
          d.syncStuckEnabled,
    );
  }
}
