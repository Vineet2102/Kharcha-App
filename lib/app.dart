import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'data/remote/supabase_client_provider.dart';
import 'data/sync/sync_engine.dart';
import 'routing/app_router.dart';

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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
