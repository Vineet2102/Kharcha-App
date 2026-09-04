import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around `flutter_local_notifications` (spec §11.12, D6:
/// local-only notifications, no push/FCM). Brought forward from Phase 13
/// because T-8.5 (budget alerts) is the first feature that needs to fire
/// one — [init] is idempotent, so Phase 13's daily-reminder/monthly-summary
/// scheduling can call it again (or just rely on this one) without issue.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
    _initialized = true;
  }

  /// Fires an immediate (non-scheduled) notification, e.g. a budget alert
  /// (spec §11.7). [id] should be stable per logical notification (the same
  /// budget re-notifying replaces its own earlier notification rather than
  /// stacking a new one).
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        'budget_alerts',
        'Budget alerts',
        channelDescription:
            'Alerts when a budget crosses its warning or exceeded threshold',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
    ),
  );
}
