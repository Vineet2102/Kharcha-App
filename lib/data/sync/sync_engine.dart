import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db/daos/outbox_dao.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../remote/supabase_client_provider.dart';
import '../repositories/profile_repository.dart';
import 'outbox_processor.dart';
import 'pull_service.dart';
import 'realtime_listener.dart';
import 'recurring_posting_engine.dart';
import 'sync_state.dart';
import 'sync_state_controller.dart';

part 'sync_engine.g.dart';

/// Orchestrates the sync cycle (spec §9.6, T-4.5): single-flight lock, push
/// then pull, publishing [SyncState] as it goes. Owns the connectivity
/// subscription (trigger 3: offline → online) and the 5-minute periodic
/// timer (trigger 6); [sync] is public so app-lifecycle code can drive
/// triggers 1 (app start), 2 (resume), 4 (pull-to-refresh) and 5 (after a
/// local write) once those exist.
class SyncEngine {
  SyncEngine({
    required this.client,
    required this.connectivity,
    required this.outboxProcessor,
    required this.pullService,
    required this.realtimeListener,
    required this.recurringPostingEngine,
    required this.outboxDao,
    required this.publish,
    required this.getHouseholdId,
  });

  final SupabaseClient client;
  final ConnectivityService connectivity;
  final OutboxProcessor outboxProcessor;
  final PullService pullService;
  final RealtimeListener realtimeListener;
  final RecurringPostingEngine recurringPostingEngine;
  final OutboxDao outboxDao;
  final void Function(SyncState state) publish;

  /// Reads the signed-in member's current household id (spec T-M2.1) at
  /// call time rather than once at construction — `SyncEngine` itself is
  /// `keepAlive` and outlives any single household. Null while signed out,
  /// before the cached profile has resolved, or (from Phase M2 onward) for
  /// an account with no household yet.
  final String? Function() getHouseholdId;

  bool _syncing = false;
  bool _stopped = false;
  bool _wasOnline = true;
  Timer? _periodicTimer;
  StreamSubscription<bool>? _connectivitySub;

  /// Idempotent — safe to call repeatedly (e.g. once at app boot regardless
  /// of auth state; [sync] itself no-ops while signed out).
  void start() {
    _stopped = false;
    _periodicTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => sync(),
    );
    _connectivitySub ??= connectivity.onStatusChange.listen((online) {
      final cameOnline = online && !_wasOnline;
      _wasOnline = online;
      if (cameOnline) unawaited(sync());
    });
  }

  /// Cancels the periodic timer, the connectivity subscription, and the
  /// Realtime channel, and makes any in-flight [sync] abort at its next
  /// checkpoint rather than write after sign-out wipes the local DB. Call
  /// [start] again to resume (e.g. on the next sign-in).
  void stop() {
    _stopped = true;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
    realtimeListener.stop();
  }

  Future<void> sync() async {
    // The single-flight lock must be set synchronously, before the first
    // `await` — otherwise two calls fired back-to-back both pass this check
    // before either reaches the line that sets it, and both run a full
    // cycle.
    if (_syncing || _stopped) return;
    if (client.auth.currentSession == null) return;
    _syncing = true;

    try {
      if (!await connectivity.isOnline) {
        publish(SyncOffline(pendingCount: await outboxDao.pendingCount()));
        return;
      }

      publish(const SyncRunning(step: 'push'));
      await outboxProcessor.process();
      if (_stopped) return;

      // No household to sync against yet (signed in but not yet joined/
      // created one — the full no-household behaviour is T-M2.7's; this is
      // just the minimal guard so a null id here can't reach `pullAll`).
      final householdId = getHouseholdId();
      if (householdId == null) {
        publish(SyncIdle(lastSyncedAt: DateTime.now()));
        return;
      }

      publish(const SyncRunning(step: 'pull'));
      await pullService.pullAll(householdId);
      if (_stopped) return;

      // Recurring posting (spec §11.8, T-9.3) runs after the pull, so an
      // occurrence another device already posted for a shared rule is
      // visible locally before this device decides whether to post its
      // own — then pushes again immediately so a freshly-posted occurrence
      // (or an advanced `next_due_date`) doesn't wait for the next cycle.
      await recurringPostingEngine.run(householdId);
      if (_stopped) return;
      await outboxProcessor.process();
      if (_stopped) return;

      realtimeListener.start(householdId);

      final pending = await outboxDao.pendingCount();
      if (await outboxDao.hasStuckEntries()) {
        publish(
          SyncError(
            message:
                'Some changes could not be synced. Check Settings for details.',
            pendingCount: pending,
          ),
        );
      } else {
        publish(SyncIdle(lastSyncedAt: DateTime.now()));
      }
    } catch (error, stackTrace) {
      AppLogger.instance.error('Sync cycle failed', error, stackTrace);
      publish(
        SyncError(
          message: ErrorMapper.map(error).message,
          pendingCount: await outboxDao.pendingCount(),
        ),
      );
    } finally {
      _syncing = false;
    }
  }
}

@Riverpod(keepAlive: true)
SyncEngine syncEngine(Ref ref) {
  final engine = SyncEngine(
    client: ref.watch(supabaseClientProvider),
    connectivity: ref.watch(connectivityServiceProvider),
    outboxProcessor: ref.watch(outboxProcessorProvider),
    pullService: ref.watch(pullServiceProvider),
    realtimeListener: ref.watch(realtimeListenerProvider),
    recurringPostingEngine: ref.watch(recurringPostingEngineProvider),
    outboxDao: ref.watch(appDatabaseProvider).outboxDao,
    publish: (state) =>
        ref.read(syncStateControllerProvider.notifier).publish(state),
    getHouseholdId: () => ref.read(currentHouseholdIdProvider),
  );
  ref.onDispose(engine.stop);
  return engine;
}
