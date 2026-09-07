import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/daos/outbox_dao.dart';
import 'package:kharcha/core/db/daos/sync_meta_dao.dart';
import 'package:kharcha/core/network/connectivity_service.dart';
import 'package:kharcha/data/sync/outbox_processor.dart';
import 'package:kharcha/data/sync/pull_service.dart';
import 'package:kharcha/data/sync/realtime_listener.dart';
import 'package:kharcha/data/sync/recurring_posting_engine.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/data/sync/sync_state.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockOutboxProcessor extends Mock implements OutboxProcessor {}

class MockPullService extends Mock implements PullService {}

class MockRealtimeListener extends Mock implements RealtimeListener {}

class MockRecurringPostingEngine extends Mock
    implements RecurringPostingEngine {}

class MockOutboxDao extends Mock implements OutboxDao {}

class MockSyncMetaDao extends Mock implements SyncMetaDao {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late MockConnectivityService connectivity;
  late MockOutboxProcessor outboxProcessor;
  late MockPullService pullService;
  late MockRealtimeListener realtimeListener;
  late MockRecurringPostingEngine recurringPostingEngine;
  late MockOutboxDao outboxDao;
  late MockSyncMetaDao syncMetaDao;
  late List<SyncState> published;
  late int refreshOwnProfileCalls;
  late int wipeHouseholdDataCalls;
  late String? householdId;
  late SyncEngine engine;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.currentSession).thenReturn(MockSession());

    connectivity = MockConnectivityService();
    outboxProcessor = MockOutboxProcessor();
    pullService = MockPullService();
    realtimeListener = MockRealtimeListener();
    when(() => realtimeListener.start(any())).thenReturn(null);
    recurringPostingEngine = MockRecurringPostingEngine();
    when(() => recurringPostingEngine.run(any())).thenAnswer((_) async {});
    outboxDao = MockOutboxDao();
    when(() => outboxDao.pendingCount()).thenAnswer((_) async => 0);
    when(() => outboxDao.hasStuckEntries()).thenAnswer((_) async => false);
    syncMetaDao = MockSyncMetaDao();
    when(() => syncMetaDao.anyStoredHouseholdId())
        .thenAnswer((_) async => 'household-1');

    published = [];
    refreshOwnProfileCalls = 0;
    wipeHouseholdDataCalls = 0;
    householdId = 'household-1';
    engine = SyncEngine(
      client: client,
      connectivity: connectivity,
      outboxProcessor: outboxProcessor,
      pullService: pullService,
      realtimeListener: realtimeListener,
      recurringPostingEngine: recurringPostingEngine,
      outboxDao: outboxDao,
      syncMetaDao: syncMetaDao,
      publish: published.add,
      getHouseholdId: () => householdId,
      refreshOwnProfile: () async {
        refreshOwnProfileCalls++;
      },
      wipeHouseholdData: () async {
        wipeHouseholdDataCalls++;
      },
    );
  });

  test('offline: publishes SyncOffline without touching the network', () async {
    when(() => connectivity.isOnline).thenAnswer((_) async => false);
    when(() => outboxDao.pendingCount()).thenAnswer((_) async => 3);

    await engine.sync();

    verifyNever(() => outboxProcessor.process());
    verifyNever(() => pullService.pullAll(any()));
    expect(published, hasLength(1));
    expect(published.single, isA<SyncOffline>());
    expect((published.single as SyncOffline).pendingCount, 3);
  });

  test(
    'a rapid double-trigger runs the cycle only once (single-flight lock)',
    () async {
      when(() => connectivity.isOnline).thenAnswer((_) async => true);
      final gate = Completer<void>();
      when(() => outboxProcessor.process()).thenAnswer((_) => gate.future);
      when(() => pullService.pullAll(any())).thenAnswer((_) async {});

      final first = engine.sync();
      final second = engine.sync(); // fired while the first is still mid-flight
      gate.complete();
      await first;
      await second;

      // Pushed once before the pull, once more after the recurring posting
      // engine runs (so a freshly-posted occurrence doesn't wait for the
      // next cycle) — both within this single cycle.
      verify(() => outboxProcessor.process()).called(2);
      verify(() => pullService.pullAll(any())).called(1);
      verify(() => recurringPostingEngine.run(any())).called(1);
    },
  );

  test('no signed-in session: sync() is a no-op', () async {
    when(() => auth.currentSession).thenReturn(null);
    when(() => connectivity.isOnline).thenAnswer((_) async => true);

    await engine.sync();

    verifyNever(() => outboxProcessor.process());
    expect(published, isEmpty);
  });

  test('after stop(), sync() no-ops even though a session exists', () async {
    when(() => connectivity.isOnline).thenAnswer((_) async => true);
    engine.stop();

    await engine.sync();

    verifyNever(() => outboxProcessor.process());
  });

  test('a successful cycle publishes SyncIdle', () async {
    when(() => connectivity.isOnline).thenAnswer((_) async => true);
    when(() => outboxProcessor.process()).thenAnswer((_) async {});
    when(() => pullService.pullAll(any())).thenAnswer((_) async {});

    await engine.sync();

    expect(published.last, isA<SyncIdle>());
  });

  test('stuck outbox entries publish SyncError instead of SyncIdle, without '
      'throwing', () async {
    when(() => connectivity.isOnline).thenAnswer((_) async => true);
    when(() => outboxProcessor.process()).thenAnswer((_) async {});
    when(() => pullService.pullAll(any())).thenAnswer((_) async {});
    when(() => outboxDao.hasStuckEntries()).thenAnswer((_) async => true);
    when(() => outboxDao.pendingCount()).thenAnswer((_) async => 2);

    await engine.sync();

    expect(published.last, isA<SyncError>());
    expect((published.last as SyncError).pendingCount, 2);
  });

  test('an exception mid-cycle is caught, logged, and published as SyncError '
      'rather than propagating', () async {
    when(() => connectivity.isOnline).thenAnswer((_) async => true);
    when(() => outboxProcessor.process())
        .thenThrow(const SocketException('no route to host'));
    when(() => outboxDao.pendingCount()).thenAnswer((_) async => 1);

    await engine.sync();

    expect(published.last, isA<SyncError>());
    expect((published.last as SyncError).pendingCount, 1);
  });

  test('a stop() mid-cycle aborts before the pull runs', () async {
    when(() => connectivity.isOnline).thenAnswer((_) async => true);
    when(() => outboxProcessor.process()).thenAnswer((_) async {
      engine.stop();
    });

    await engine.sync();

    verifyNever(() => pullService.pullAll(any()));
  });

  group('household change (spec §9.6 rule 3, T-M2.7)', () {
    setUp(() {
      when(() => connectivity.isOnline).thenAnswer((_) async => true);
      when(() => outboxProcessor.process()).thenAnswer((_) async {});
      when(() => pullService.pullAll(any())).thenAnswer((_) async {});
    });

    test('a stored household id different from the current one wipes local '
        'data before the outbox is pushed', () async {
      when(() => syncMetaDao.anyStoredHouseholdId())
          .thenAnswer((_) async => 'household-OLD');

      await engine.sync();

      expect(wipeHouseholdDataCalls, 1);
      verify(() => outboxProcessor.process()).called(2);
    });

    test('no stored household id (fresh install) does not wipe', () async {
      when(() => syncMetaDao.anyStoredHouseholdId())
          .thenAnswer((_) async => null);

      await engine.sync();

      expect(wipeHouseholdDataCalls, 0);
    });

    test('the same stored household id does not wipe', () async {
      when(() => syncMetaDao.anyStoredHouseholdId())
          .thenAnswer((_) async => 'household-1');

      await engine.sync();

      expect(wipeHouseholdDataCalls, 0);
    });

    test('leaving a household (current id becomes null) still wipes the '
        'now-stale local data', () async {
      householdId = null;
      when(() => syncMetaDao.anyStoredHouseholdId())
          .thenAnswer((_) async => 'household-1');

      await engine.sync();

      expect(wipeHouseholdDataCalls, 1);
      expect(published.last, isA<SyncIdle>());
    });

    test('the own profile is refreshed before household id is trusted, even '
        'with no household at all', () async {
      householdId = null;
      when(() => syncMetaDao.anyStoredHouseholdId())
          .thenAnswer((_) async => null);

      await engine.sync();

      expect(refreshOwnProfileCalls, 1);
      expect(wipeHouseholdDataCalls, 0);
      expect(published.last, isA<SyncIdle>());
    });

    test('offline never refreshes the profile or checks for a household '
        'change', () async {
      when(() => connectivity.isOnline).thenAnswer((_) async => false);

      await engine.sync();

      expect(refreshOwnProfileCalls, 0);
      verifyNever(() => syncMetaDao.anyStoredHouseholdId());
    });
  });

  group('start()/stop()', () {
    late StreamController<bool> statusChanges;

    setUp(() {
      statusChanges = StreamController<bool>.broadcast();
      when(() => connectivity.onStatusChange)
          .thenAnswer((_) => statusChanges.stream);
      when(() => connectivity.isOnline).thenAnswer((_) async => true);
      when(() => outboxProcessor.process()).thenAnswer((_) async {});
      when(() => pullService.pullAll(any())).thenAnswer((_) async {});
    });

    tearDown(() => statusChanges.close());

    test('a transition from offline to online triggers a sync cycle', () async {
      engine.start();
      statusChanges.add(false);
      await Future<void>.delayed(Duration.zero);
      statusChanges.add(true);
      await Future<void>.delayed(Duration.zero);

      verify(() => outboxProcessor.process()).called(greaterThan(0));
    });

    test(
      'staying online on successive events does not re-trigger a cycle',
      () async {
        engine.start();
        statusChanges.add(true);
        await Future<void>.delayed(Duration.zero);
        statusChanges.add(true);
        await Future<void>.delayed(Duration.zero);

        verifyNever(() => outboxProcessor.process());
      },
    );

    test(
      'stop() tears down the timer, subscription, and realtime listener',
      () async {
        when(() => realtimeListener.stop()).thenReturn(null);
        engine.start();

        engine.stop();
        statusChanges.add(true); // must no longer be observed

        await Future<void>.delayed(Duration.zero);

        verifyNever(() => outboxProcessor.process());
        verify(() => realtimeListener.stop()).called(1);
      },
    );

    test('start() is idempotent — calling it twice arms only one timer/subscription', () async {
      engine.start();
      engine.start();
      statusChanges.add(false);
      await Future<void>.delayed(Duration.zero);
      statusChanges.add(true);
      await Future<void>.delayed(Duration.zero);

      // A single online transition triggers exactly one cycle, not two —
      // proving the second start() didn't attach a duplicate listener.
      verify(() => outboxProcessor.process()).called(2);
    });
  });
}
