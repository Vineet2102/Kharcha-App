import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/sync/entity_sync_adapters.dart';
import 'package:kharcha/data/sync/outbox_processor.dart';

import 'fake_entity_sync_adapter.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late AppDatabase db;
  late MockSupabaseClient client;
  late List<String> callLog;
  late FakeEntitySyncAdapter categoryAdapter;
  late FakeEntitySyncAdapter expenseAdapter;
  late Map<String, EntitySyncAdapter> adaptersByKey;
  late OutboxProcessor processor;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = MockSupabaseClient();
    callLog = [];
    categoryAdapter = FakeEntitySyncAdapter('category', callLog: callLog);
    expenseAdapter = FakeEntitySyncAdapter('expense', callLog: callLog);
    adaptersByKey = {'category': categoryAdapter, 'expense': expenseAdapter};
    processor = OutboxProcessor(
      db: db,
      client: client,
      adaptersByKey: adaptersByKey,
    );
  });

  tearDown(() => db.close());

  Future<void> enqueue({
    required String entity,
    required String entityId,
    String op = 'upsert',
    Map<String, dynamic>? payload,
    DateTime? createdAt,
  }) {
    return db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: '${entity}_$entityId',
        entity: entity,
        entityId: entityId,
        op: op,
        payload: jsonEncode(payload ?? {'id': entityId}),
        createdAt: createdAt ?? DateTime.now().toUtc(),
      ),
    );
  }

  test(
    'pushes category/payment_method before expense (dependency ordering)',
    () async {
      // Enqueued in the "wrong" order — expense first — to prove ordering
      // comes from the entity, not from enqueue order.
      await enqueue(
        entity: 'expense',
        entityId: 'e1',
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await enqueue(
        entity: 'category',
        entityId: 'c1',
        createdAt: DateTime.utc(2026, 1, 2),
      );

      await processor.process();

      expect(callLog, ['category:upsert:c1', 'expense:upsert:e1']);
    },
  );

  test('keeps FIFO order within the same entity', () async {
    await enqueue(
      entity: 'expense',
      entityId: 'e1',
      createdAt: DateTime.utc(2026, 1, 1),
    );
    await enqueue(
      entity: 'expense',
      entityId: 'e2',
      createdAt: DateTime.utc(2026, 1, 2),
    );

    await processor.process();

    expect(callLog, ['expense:upsert:e1', 'expense:upsert:e2']);
  });

  test(
    'a successful push removes the outbox entry and marks the local row synced',
    () async {
      await enqueue(entity: 'expense', entityId: 'e1');

      await processor.process();

      expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
      expect(expenseAdapter.syncedIds, ['e1']);
    },
  );

  test(
    'a permanent failure (RLS denial) marks the entry failed and never retries',
    () async {
      expenseAdapter.errorToThrow = const PostgrestException(
        message: 'denied',
        code: '42501',
      );
      await enqueue(entity: 'expense', entityId: 'e1');

      await processor.process();

      final rows = await (db.select(db.outboxEntries)).get();
      expect(rows, hasLength(1));
      expect(rows.single.status, 'failed');
      expect(rows.single.nextAttemptAt, isNull);

      // A second process() call must not retry a failed entry.
      await processor.process();
      expect(
        expenseAdapter.upserts,
        isEmpty,
      ); // pushUpsert threw both times, never succeeded
      expect(
        await db.outboxDao.dueEntries(
          DateTime.now().toUtc().add(const Duration(days: 1)),
        ),
        isEmpty,
      );
    },
  );

  test('a transient failure (network) increments attempts and schedules a backoff retry', () async {
    expenseAdapter.errorToThrow = const SocketException('no route to host');
    await enqueue(entity: 'expense', entityId: 'e1');

    await processor.process();

    final rows = await (db.select(db.outboxEntries)).get();
    expect(rows, hasLength(1));
    expect(rows.single.status, 'pending');
    expect(rows.single.attempts, 1);
    expect(rows.single.nextAttemptAt, isNotNull);
    expect(rows.single.nextAttemptAt!.isAfter(DateTime.now().toUtc()), isTrue);
  });

  test('a delete op calls pushSoftDelete', () async {
    await enqueue(entity: 'expense', entityId: 'e1', op: 'delete');

    await processor.process();

    expect(expenseAdapter.deletes, ['e1']);
  });

  group('recurring occurrence duplicate (T-9.4)', () {
    Future<void> insertLocalExpense(String id) => db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: id,
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 500,
        spentAt: DateTime.utc(2026, 1, 1),
        spentOn: DateTime.utc(2026, 1, 1),
        recurringRuleId: const Value('r1'),
        occurrenceDate: Value(DateTime.utc(2026, 1, 1)),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    test(
      'a unique-index violation on a recurring occurrence is treated as '
      'success: the local duplicate is discarded, not marked failed',
      () async {
        await insertLocalExpense('e2');
        expenseAdapter.errorToThrow = const PostgrestException(
          message:
              'duplicate key value violates unique constraint '
              '"expenses_recurrence_unique"',
          code: '23505',
        );
        await enqueue(
          entity: 'expense',
          entityId: 'e2',
          payload: {
            'id': 'e2',
            'recurring_rule_id': 'r1',
            'occurrence_date': '2026-01-01',
          },
        );

        await processor.process();

        expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
        final rows = await (db.select(db.outboxEntries)).get();
        expect(rows, isEmpty); // not parked as 'failed'
        expect(await db.expenseDao.findById('e2'), isNull);
      },
    );

    test('a plain unique violation with no recurring_rule_id is still a '
        'normal permanent failure', () async {
      expenseAdapter.errorToThrow = const PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      await enqueue(entity: 'expense', entityId: 'e3');

      await processor.process();

      final rows = await (db.select(db.outboxEntries)).get();
      expect(rows, hasLength(1));
      expect(rows.single.status, 'failed');
    });

    test('two devices racing: the first push succeeds, the second is '
        'discarded as a duplicate', () async {
      await insertLocalExpense('e1');
      await insertLocalExpense('e2');
      expenseAdapter.upsertErrorQueue.addAll([
        null,
        const PostgrestException(
          message:
              'duplicate key value violates unique constraint '
              '"expenses_recurrence_unique"',
          code: '23505',
        ),
      ]);
      await enqueue(
        entity: 'expense',
        entityId: 'e1',
        payload: {
          'id': 'e1',
          'recurring_rule_id': 'r1',
          'occurrence_date': '2026-01-01',
        },
        createdAt: DateTime.utc(2026, 1, 1),
      );
      await enqueue(
        entity: 'expense',
        entityId: 'e2',
        payload: {
          'id': 'e2',
          'recurring_rule_id': 'r1',
          'occurrence_date': '2026-01-01',
        },
        createdAt: DateTime.utc(2026, 1, 2),
      );

      await processor.process();

      expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
      expect(await (db.select(db.outboxEntries)).get(), isEmpty);
      expect(await db.expenseDao.findById('e1'), isNotNull);
      expect(await db.expenseDao.findById('e2'), isNull);
    });
  });
}
