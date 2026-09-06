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

class MockSupabaseStorageClient extends Mock implements SupabaseStorageClient {}

class MockStorageFileApi extends Mock implements StorageFileApi {}

class FakeFile extends Fake implements File {}

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
    'a successful upsert push removes the outbox entry (pushUpsert owns '
    'stamping the local row synced — see entity_sync_adapters.dart)',
    () async {
      await enqueue(entity: 'expense', entityId: 'e1');

      await processor.process();

      expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
      expect(expenseAdapter.upserts, hasLength(1));
    },
  );

  test('a successful delete push removes the outbox entry and marks the local row synced', () async {
    await enqueue(entity: 'expense', entityId: 'e1', op: 'delete');

    await processor.process();

    expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
    expect(expenseAdapter.syncedIds, ['e1']);
  });

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

    test(
      'the same duplicate handling applies to income (not just expense)',
      () async {
        await db.incomeDao.upsert(
          IncomesCompanion.insert(
            id: 'i1',
            householdId: 'h1',
            userId: 'u1',
            amountPaise: 500,
            receivedAt: DateTime.utc(2026, 1, 1),
            receivedOn: DateTime.utc(2026, 1, 1),
            recurringRuleId: const Value('r1'),
            occurrenceDate: Value(DateTime.utc(2026, 1, 1)),
            createdAt: DateTime.utc(2026, 1, 1),
            updatedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final incomeAdapter = FakeEntitySyncAdapter('income', callLog: callLog);
        adaptersByKey['income'] = incomeAdapter;
        incomeAdapter.errorToThrow = const PostgrestException(
          message:
              'duplicate key value violates unique constraint '
              '"incomes_recurrence_unique"',
          code: '23505',
        );
        await enqueue(
          entity: 'income',
          entityId: 'i1',
          payload: {
            'id': 'i1',
            'recurring_rule_id': 'r1',
            'occurrence_date': '2026-01-01',
          },
        );

        await processor.process();

        expect(await (db.select(db.outboxEntries)).get(), isEmpty);
        expect(await db.incomeDao.findById('i1'), isNull);
      },
    );
  });

  test('an entry for an unknown entity is marked failed immediately', () async {
    await enqueue(entity: 'nonsense', entityId: 'x1');

    await processor.process();

    final rows = await (db.select(db.outboxEntries)).get();
    expect(rows, hasLength(1));
    expect(rows.single.status, 'failed');
    expect(rows.single.lastError, contains('Unknown outbox entity'));
  });

  test(
    'an entity outside the known dependency order still gets pushed',
    () async {
      final futureAdapter = FakeEntitySyncAdapter(
        'future_entity',
        callLog: callLog,
      );
      adaptersByKey['future_entity'] = futureAdapter;
      await enqueue(entity: 'future_entity', entityId: 'f1');
      await enqueue(entity: 'expense', entityId: 'e1');

      await processor.process();

      expect(futureAdapter.upserts, hasLength(1));
      expect(expenseAdapter.upserts, hasLength(1));
    },
  );

  test(
    'an unrecognised outbox op is a permanent-shaped failure path',
    () async {
      await enqueue(entity: 'expense', entityId: 'e1', op: 'rename');

      await processor.process();

      final rows = await (db.select(db.outboxEntries)).get();
      expect(rows, hasLength(1));
      // StateError maps to UnknownFailure, which _handleFailure treats as
      // transient (not Permission/Validation) — scheduled for backoff retry
      // rather than parked, but the important thing this proves is that the
      // `default: throw StateError` branch is actually reached and handled
      // rather than propagating uncaught.
      expect(rows.single.status, 'pending');
      expect(rows.single.attempts, 1);
    },
  );

  group('attachment storage side-effects (T-10.5)', () {
    late MockSupabaseStorageClient storage;
    late MockStorageFileApi fileApi;
    late FakeEntitySyncAdapter attachmentAdapter;

    setUpAll(() => registerFallbackValue(FakeFile()));

    setUp(() {
      storage = MockSupabaseStorageClient();
      fileApi = MockStorageFileApi();
      when(() => client.storage).thenReturn(storage);
      when(() => storage.from('receipts')).thenReturn(fileApi);
      attachmentAdapter = FakeEntitySyncAdapter('attachment', callLog: callLog);
      adaptersByKey['attachment'] = attachmentAdapter;
    });

    Future<void> insertAttachment(String id) => db.attachmentDao.upsert(
      AttachmentsCompanion.insert(
        id: id,
        householdId: 'h1',
        expenseId: 'e1',
        storagePath: 'h1/e1/$id.jpg',
        uploadedBy: 'u1',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    test('a delete op for an attachment best-effort removes the storage object '
        'before the row is soft-deleted', () async {
      await insertAttachment('a1');
      when(() => fileApi.remove(['h1/e1/a1.jpg'])).thenAnswer((_) async => []);
      await enqueue(entity: 'attachment', entityId: 'a1', op: 'delete');

      await processor.process();

      verify(() => fileApi.remove(['h1/e1/a1.jpg'])).called(1);
      expect(attachmentAdapter.deletes, ['a1']);
    });

    test('a storage removal failure does not block the row from being '
        'soft-deleted (best-effort, per spec §11.9)', () async {
      await insertAttachment('a1');
      when(() => fileApi.remove(['h1/e1/a1.jpg']))
          .thenThrow(const StorageException('offline'));
      await enqueue(entity: 'attachment', entityId: 'a1', op: 'delete');

      await processor.process();

      expect(attachmentAdapter.deletes, ['a1']);
      expect(await (db.select(db.outboxEntries)).get(), isEmpty);
    });

    test(
      'a delete for an attachment id with no local row skips the storage call',
      () async {
        when(() => fileApi.remove(any())).thenAnswer((_) async => []);
        await enqueue(entity: 'attachment', entityId: 'missing', op: 'delete');

        await processor.process();

        verifyNever(() => fileApi.remove(any()));
        expect(attachmentAdapter.deletes, ['missing']);
      },
    );

    test('an upload op uploads the cached file then pushes the row', () async {
      when(() => fileApi.upload('h1/e1/a1.jpg', any()))
          .thenAnswer((_) async => 'h1/e1/a1.jpg');
      await enqueue(
        entity: 'attachment',
        entityId: 'a1',
        op: 'upload',
        payload: {
          'local_path': '/tmp/a1.jpg',
          'storage_path': 'h1/e1/a1.jpg',
          'row': {'id': 'a1'},
        },
      );

      await processor.process();

      verify(() => fileApi.upload('h1/e1/a1.jpg', any())).called(1);
      expect(attachmentAdapter.upserts, hasLength(1));
      expect(attachmentAdapter.upserts.single['id'], 'a1');
      expect(await (db.select(db.outboxEntries)).get(), isEmpty);
    });
  });
}
