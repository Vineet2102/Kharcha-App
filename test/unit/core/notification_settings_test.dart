import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kharcha/core/notifications/notification_settings.dart';

void main() {
  group('NotificationSettings.copyWith', () {
    test('keeps every field unchanged when nothing is passed', () {
      const settings = NotificationSettings();
      final copy = settings.copyWith();

      expect(copy.dailyReminderEnabled, settings.dailyReminderEnabled);
      expect(copy.dailyReminderHour, settings.dailyReminderHour);
      expect(copy.dailyReminderMinute, settings.dailyReminderMinute);
      expect(copy.budgetAlertsEnabled, settings.budgetAlertsEnabled);
      expect(copy.monthlySummaryEnabled, settings.monthlySummaryEnabled);
      expect(copy.recurringDueEnabled, settings.recurringDueEnabled);
      expect(copy.syncStuckEnabled, settings.syncStuckEnabled);
    });

    test('overrides only the fields passed', () {
      const settings = NotificationSettings();
      final copy = settings.copyWith(
        dailyReminderEnabled: false,
        dailyReminderHour: 8,
        dailyReminderMinute: 30,
        budgetAlertsEnabled: false,
        monthlySummaryEnabled: false,
        recurringDueEnabled: false,
        syncStuckEnabled: false,
      );

      expect(copy.dailyReminderEnabled, isFalse);
      expect(copy.dailyReminderHour, 8);
      expect(copy.dailyReminderMinute, 30);
      expect(copy.budgetAlertsEnabled, isFalse);
      expect(copy.monthlySummaryEnabled, isFalse);
      expect(copy.recurringDueEnabled, isFalse);
      expect(copy.syncStuckEnabled, isFalse);
    });
  });

  group('NotificationSettings defaults (spec §11.12)', () {
    test('everything is on by default, reminder at 21:00', () {
      const settings = NotificationSettings();

      expect(settings.dailyReminderEnabled, isTrue);
      expect(settings.dailyReminderHour, 21);
      expect(settings.dailyReminderMinute, 0);
      expect(settings.budgetAlertsEnabled, isTrue);
      expect(settings.monthlySummaryEnabled, isTrue);
      expect(settings.recurringDueEnabled, isTrue);
      expect(settings.syncStuckEnabled, isTrue);
    });
  });

  group('SharedPreferences.loadNotificationSettings', () {
    test(
      'falls back to defaults when nothing has been persisted yet',
      () async {
        SharedPreferences.setMockInitialValues({});
        final prefs = await SharedPreferences.getInstance();

        final settings = prefs.loadNotificationSettings();

        expect(settings.dailyReminderEnabled, isTrue);
        expect(settings.dailyReminderHour, 21);
        expect(settings.dailyReminderMinute, 0);
        expect(settings.budgetAlertsEnabled, isTrue);
        expect(settings.monthlySummaryEnabled, isTrue);
        expect(settings.recurringDueEnabled, isTrue);
        expect(settings.syncStuckEnabled, isTrue);
      },
    );

    test('reads back every persisted value, overriding the defaults', () async {
      SharedPreferences.setMockInitialValues({
        NotificationSettingsKeys.dailyReminderEnabled: false,
        NotificationSettingsKeys.dailyReminderHour: 7,
        NotificationSettingsKeys.dailyReminderMinute: 45,
        NotificationSettingsKeys.budgetAlertsEnabled: false,
        NotificationSettingsKeys.monthlySummaryEnabled: false,
        NotificationSettingsKeys.recurringDueEnabled: false,
        NotificationSettingsKeys.syncStuckEnabled: false,
      });
      final prefs = await SharedPreferences.getInstance();

      final settings = prefs.loadNotificationSettings();

      expect(settings.dailyReminderEnabled, isFalse);
      expect(settings.dailyReminderHour, 7);
      expect(settings.dailyReminderMinute, 45);
      expect(settings.budgetAlertsEnabled, isFalse);
      expect(settings.monthlySummaryEnabled, isFalse);
      expect(settings.recurringDueEnabled, isFalse);
      expect(settings.syncStuckEnabled, isFalse);
    });
  });
}
