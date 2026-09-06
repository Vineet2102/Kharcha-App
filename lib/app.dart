import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/constants/app_constants.dart';
import 'core/notifications/notification_service.dart';
import 'data/remote/supabase_client_provider.dart';
import 'data/repositories/budget_alert_service.dart';
import 'data/repositories/notification_scheduler.dart';
import 'data/repositories/update_check_repository.dart';
import 'data/sync/sync_engine.dart';
import 'routing/app_router.dart';
import 'routing/root_navigator_key.dart';

/// Visual design is out of scope (spec §0 rule 6) — Material 3 defaults
/// with a single seed colour, following the system light/dark setting.
///
/// Also wires 2 of the sync engine's 6 trigger points (spec §9.6, T-4.5):
/// app start once auth resolves (1) and app resume, throttled to once per
/// 30s (2). The other four — connectivity (3) and the periodic timer (6)
/// are owned by `SyncEngine.start()` itself; pull-to-refresh (4) and
/// after-a-local-write (5) will be wired from the screens/repositories that
/// create them in Phase 5+.
class KharchaApp extends ConsumerStatefulWidget {
  const KharchaApp({super.key});

  @override
  ConsumerState<KharchaApp> createState() => _KharchaAppState();
}

class _KharchaAppState extends ConsumerState<KharchaApp>
    with WidgetsBindingObserver {
  static const _resumeThrottle = Duration(seconds: 30);
  DateTime? _lastResumeSync;
  StreamSubscription<String>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final engine = ref.read(syncEngineProvider);
    engine.start();
    // Covers the boot-with-an-already-persisted-session case; `sync()` is a
    // harmless no-op if nothing is signed in yet. The `ref.listen` in
    // `build()` covers a sign-in that happens later in this app session.
    engine.sync();

    // T-13.2: recurring notifications are re-armed on every app start,
    // since Android clears alarms on reboot and this app has no background
    // execution to re-arm them any other way.
    ref
        .read(notificationSchedulerProvider)
        .runAll(AppConstants.seedHouseholdId);

    // T-14.6: at most once per 24h (the repository's own throttle) — see
    // `UpdateCheckRepository.checkForUpdates`.
    ref.read(updateCheckControllerProvider.notifier).check();

    // T-13.4: deep-link a tapped notification into its target route. A
    // foreground tap arrives on this stream; a cold-start tap (the
    // notification is what launched the app) is handled once the first
    // frame has mounted the router, below.
    _notificationTapSub = NotificationService.instance.onTap.listen(
      _openNotificationTarget,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final launchPayload = NotificationService.instance.consumeLaunchPayload();
      if (launchPayload != null) _openNotificationTarget(launchPayload);
    });
  }

  void _openNotificationTarget(String path) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return;
    GoRouter.of(context).push(path);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _notificationTapSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final now = DateTime.now();
    if (_lastResumeSync != null &&
        now.difference(_lastResumeSync!) < _resumeThrottle) {
      return;
    }
    _lastResumeSync = now;
    ref.read(syncEngineProvider).sync();
    // Budget alerts and the rest of the notification types are evaluated on
    // every resume regardless of the sync throttle above (spec §11.7/
    // §11.12) — both are local reads, not network calls.
    ref.read(budgetAlertServiceProvider).evaluate(AppConstants.seedHouseholdId);
    ref
        .read(notificationSchedulerProvider)
        .runAll(AppConstants.seedHouseholdId);
    ref.read(updateCheckControllerProvider.notifier).check();
  }

  Future<void> _showBlockedUpdateDialog(Blocked blocked) {
    final context = rootNavigatorKey.currentContext;
    if (context == null) return Future.value();
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('Update required'),
          content: const Text(
            'This version is too old to sync safely. Please update.',
          ),
          actions: [
            FilledButton(
              onPressed: blocked.release.downloadUrl == null
                  ? null
                  : () => launchUrl(
                      Uri.parse(blocked.release.downloadUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
              child: const Text('Get it'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Trigger 1: kick a sync as soon as a session exists (sign-in, or an
    // already-persisted session resolving at boot).
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous == null && next != null) {
        ref.read(syncEngineProvider).sync();
      }
    });

    // T-14.6: `min_supported > current build` is the emergency brake — a
    // non-dismissible dialog, unlike the ordinary UpdateAvailable banner
    // (rendered on the Dashboard itself, see `update_banner.dart`).
    ref.listen(updateCheckControllerProvider, (previous, next) {
      if (next is Blocked) _showBlockedUpdateDialog(next);
    });

    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      routerConfig: router,
    );
  }
}
