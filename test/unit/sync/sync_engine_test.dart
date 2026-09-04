import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/daos/outbox_dao.dart';
import 'package:kharcha/core/network/connectivity_service.dart';
import 'package:kharcha/data/sync/outbox_processor.dart';
import 'package:kharcha/data/sync/pull_service.dart';
import 'package:kharcha/data/sync/realtime_listener.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/data/sync/sync_state.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockOutboxProcessor extends Mock implements OutboxProcessor {}

class MockPullService extends Mock implements PullService {}

class MockRealtimeListener extends Mock implements RealtimeListener {}

class MockOutboxDao extends Mock implements OutboxDao {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late MockConnectivityService connectivity;
  late MockOutboxProcessor outboxProcessor;
  late MockPullService pullService;
  late MockRealtimeListener realtimeListener;
  late MockOutboxDao outboxDao;
  late List<SyncState> published;
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
    outboxDao = MockOutboxDao();
    when(() => outboxDao.pendingCount()).thenAnswer((_) async => 0);
    when(() => outboxDao.hasStuckEntries()).thenAnswer((_) async => false);

    published = [];
    engine = SyncEngine(
      client: client,
      connectivity: connectivity,
      outboxProcessor: outboxProcessor,
      pullService: pullService,
      realtimeListener: realtimeListener,
      outboxDao: outboxDao,
      publish: published.add,
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

      verify(() => outboxProcessor.process()).called(1);
      verify(() => pullService.pullAll(any())).called(1);
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
}
