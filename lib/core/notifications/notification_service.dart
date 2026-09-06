import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// Thin wrapper around `flutter_local_notifications` (spec §11.12, D6:
/// local-only notifications, no push/FCM). Brought forward from Phase 13 in
/// Phase 8 — T-8.5's budget alerts are the first feature that needs to fire
/// one; Phase 13 (T-13.1/T-13.2/T-13.4) adds `scheduleAt`/`cancel` and the
/// tap-to-deep-link plumbing on top of this same initialized plugin.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<String> _tapController =
      StreamController<String>.broadcast();
  bool _initialized = false;
  String? _pendingLaunchPayload;

  /// Fires the tapped notification's `payload` whenever the user taps one
  /// while the app is already running (spec §11.12, T-13.4). A cold-start
  /// tap (the notification is what launched the app) is not delivered here
  /// — see [consumeLaunchPayload].
  Stream<String> get onTap => _tapController.stream;

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
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        if (payload != null && payload.isNotEmpty) _tapController.add(payload);
      },
    );

    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      _pendingLaunchPayload = launchDetails?.notificationResponse?.payload;
    }

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

  /// Returns and clears the payload of the notification that cold-launched
  /// the app, if any (spec §11.12, T-13.4). Call once, after the router has
  /// mounted (`rootNavigatorKey.currentContext` must be non-null).
  String? consumeLaunchPayload() {
    final payload = _pendingLaunchPayload;
    _pendingLaunchPayload = null;
    return payload;
  }

  /// Fires an immediate (non-scheduled) notification — a budget alert
  /// (spec §11.7) or one of Phase 13's dynamic-content types (monthly
  /// summary, recurring due, sync stuck — see DECISIONS.md for why those
  /// are "evaluated and shown immediately" rather than pre-scheduled).
  /// [id] should be stable per logical notification (the same budget
  /// re-notifying replaces its own earlier notification rather than
  /// stacking a new one). [channelId]/[channelName] group notifications in
  /// the Android system settings — every call site picks its own, rather
  /// than sharing one channel across unrelated notification types.
  Future<void> show({
    required int id,
    required String title,
    required String body,
    required String channelId,
    required String channelName,
    String? channelDescription,
    String? payload,
  }) => _plugin.show(
    id: id,
    title: title,
    body: body,
    payload: payload,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );

  /// Schedules a single, one-shot local notification at [scheduledDate]
  /// (spec §11.12, T-13.2) — deliberately not a repeating alarm. The only
  /// caller is the daily-logging-reminder (`NotificationScheduler`), which
  /// re-computes and re-arms this every app start/resume rather than
  /// relying on the OS to repeat it — see DECISIONS.md.
  ///
  /// `androidScheduleMode: inexactAllowWhileIdle` per spec §11.12: exact
  /// alarms need the `SCHEDULE_EXACT_ALARM` special-access permission,
  /// which this app deliberately avoids — arriving a few minutes late is
  /// an accepted trade-off.
  Future<void> scheduleAt({
    required int id,
    required String title,
    required String body,
    required tz.TZDateTime scheduledDate,
    required String channelId,
    required String channelName,
    String? channelDescription,
    String? payload,
  }) => _plugin.zonedSchedule(
    id: id,
    title: title,
    body: body,
    scheduledDate: scheduledDate,
    payload: payload,
    androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        channelDescription: channelDescription,
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      ),
      iOS: const DarwinNotificationDetails(),
    ),
  );

  Future<void> cancel(int id) => _plugin.cancel(id: id);
}
