import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/data/sync/pull_service.dart';
import 'package:kharcha/data/sync/realtime_listener.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockRealtimeChannel extends Mock implements RealtimeChannel {}

class MockPullService extends Mock implements PullService {}

class FakeRealtimeChannel extends Fake implements RealtimeChannel {}

void main() {
  late MockSupabaseClient client;
  late MockRealtimeChannel channel;
  late MockPullService pullService;
  late RealtimeListener listener;
  final capturedCallbacks = <String, void Function(PostgresChangePayload)>{};

  PostgresChangePayload payload() => PostgresChangePayload(
    schema: 'public',
    table: 'expenses',
    commitTimestamp: DateTime.utc(2026, 1, 1),
    eventType: PostgresChangeEvent.update,
    newRecord: const {},
    oldRecord: const {},
    errors: null,
  );

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
    registerFallbackValue(FakeRealtimeChannel());
  });

  setUp(() {
    client = MockSupabaseClient();
    channel = MockRealtimeChannel();
    pullService = MockPullService();
    capturedCallbacks.clear();

    when(() => client.channel(any())).thenReturn(channel);
    when(
      () => channel.onPostgresChanges(
        event: any(named: 'event'),
        schema: any(named: 'schema'),
        table: any(named: 'table'),
        filter: any(named: 'filter'),
        callback: any(named: 'callback'),
      ),
    ).thenAnswer((invocation) {
      final table = invocation.namedArguments[#table] as String;
      capturedCallbacks[table] =
          invocation.namedArguments[#callback]
              as void Function(PostgresChangePayload);
      return channel;
    });
    when(() => channel.subscribe()).thenReturn(channel);
    when(() => client.removeChannel(any())).thenAnswer((_) async => 'ok');
    when(() => pullService.pullEntity(any(), any())).thenAnswer((_) async {});

    listener = RealtimeListener(client: client, pullService: pullService);
  });

  test(
    'start() subscribes to all 3 watched tables, scoped to the household',
    () {
      listener.start('hh1');

      verify(() => client.channel('household-changes-hh1')).called(1);
      verify(() => channel.subscribe()).called(1);
      expect(capturedCallbacks.keys.toSet(), {
        'expenses',
        'incomes',
        'budgets',
      });
    },
  );

  test(
    'a postgres change debounces for 2s then pulls only that entity',
    () async {
      listener.start('hh1');

      capturedCallbacks['expenses']!(payload());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      verifyNever(() => pullService.pullEntity(any(), any()));

      await Future<void>.delayed(const Duration(seconds: 2));
      verify(() => pullService.pullEntity('expense', 'hh1')).called(1);
    },
  );

  test(
    'rapid successive changes to the same table collapse into one pull',
    () async {
      listener.start('hh1');

      capturedCallbacks['budgets']!(payload());
      await Future<void>.delayed(const Duration(milliseconds: 500));
      capturedCallbacks['budgets']!(payload());
      await Future<void>.delayed(const Duration(seconds: 2, milliseconds: 500));

      verify(() => pullService.pullEntity('budget', 'hh1')).called(1);
    },
  );

  test('start() called again tears down the previous channel first', () {
    listener.start('hh1');
    listener.start('hh1');

    verify(() => client.removeChannel(channel)).called(1);
    verify(() => client.channel('household-changes-hh1')).called(2);
  });

  test(
    'stop() removes the channel and cancels pending debounce timers',
    () async {
      listener.start('hh1');
      capturedCallbacks['incomes']!(payload());

      listener.stop();
      await Future<void>.delayed(const Duration(seconds: 3));

      verify(() => client.removeChannel(channel)).called(1);
      verifyNever(() => pullService.pullEntity(any(), any()));
    },
  );

  test('stop() with no active channel is a safe no-op', () {
    expect(listener.stop, returnsNormally);
    verifyNever(() => client.removeChannel(any()));
  });
}
