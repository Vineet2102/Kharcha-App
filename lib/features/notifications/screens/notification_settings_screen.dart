import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controllers/notification_settings_controller.dart';

/// Per-type notification toggles + the daily reminder's time picker (spec
/// §11.12/§11.13, T-13.3). Reachable ahead of its real Settings-screen home
/// (Phase 14) via a direct "Notifications" link, same precedent as every
/// other screen added early in this build.
class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _pickReminderTime(
    BuildContext context,
    WidgetRef ref,
    int hour,
    int minute,
  ) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
    );
    if (picked == null) return;
    await ref
        .read(notificationSettingsControllerProvider.notifier)
        .setDailyReminderTime(picked.hour, picked.minute);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(notificationSettingsControllerProvider);
    final controller = ref.read(
      notificationSettingsControllerProvider.notifier,
    );
    final reminderTime = TimeOfDay(
      hour: settings.dailyReminderHour,
      minute: settings.dailyReminderMinute,
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Daily reminder'),
            subtitle: Text(
              settings.dailyReminderEnabled
                  ? 'At ${reminderTime.format(context)} · skipped if you already logged something today'
                  : 'Off',
            ),
            value: settings.dailyReminderEnabled,
            onChanged: (v) => controller.setDailyReminderEnabled(v),
          ),
          if (settings.dailyReminderEnabled)
            ListTile(
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              title: const Text('Reminder time'),
              trailing: Text(reminderTime.format(context)),
              onTap: () => _pickReminderTime(
                context,
                ref,
                settings.dailyReminderHour,
                settings.dailyReminderMinute,
              ),
            ),
          const Divider(),
          SwitchListTile(
            title: const Text('Budget alerts'),
            subtitle: const Text('Warning and exceeded thresholds'),
            value: settings.budgetAlertsEnabled,
            onChanged: (v) => controller.setBudgetAlertsEnabled(v),
          ),
          SwitchListTile(
            title: const Text('Monthly summary'),
            subtitle: const Text("Household spend/income, 1st of each month"),
            value: settings.monthlySummaryEnabled,
            onChanged: (v) => controller.setMonthlySummaryEnabled(v),
          ),
          SwitchListTile(
            title: const Text('Recurring due'),
            subtitle: const Text(
              'Manual recurring items waiting for confirmation',
            ),
            value: settings.recurringDueEnabled,
            onChanged: (v) => controller.setRecurringDueEnabled(v),
          ),
          SwitchListTile(
            title: const Text('Sync issues'),
            subtitle: const Text("Changes that haven't synced in 24h+"),
            value: settings.syncStuckEnabled,
            onChanged: (v) => controller.setSyncStuckEnabled(v),
          ),
        ],
      ),
    );
  }
}
