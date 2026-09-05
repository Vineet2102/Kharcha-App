import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/repositories/recurring_repository.dart';
import 'package:kharcha/data/sync/recurring_posting_engine.dart';
import 'package:kharcha/domain/models/enums.dart';

void main() {
  late AppDatabase db;
  late int syncTriggerCount;
  late RecurringRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncTriggerCount = 0;
    repo = RecurringRepository(
      db,
      RecurringPostingEngine(db),
      () => syncTriggerCount++,
    );
  });
  tearDown(() => db.close());

  test(
    'create seeds next_due_date from start_date and enqueues an outbox upsert',
    () async {
      final startDate = DateTime.utc(2026, 10, 5);
      final id = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        kind: TxnKind.expense,
        title: 'Netflix',
        amountPaise: 49900,
        frequency: RecurFrequency.monthly,
        startDate: startDate,
      );

      final rule = await repo.findById(id);
      expect(rule, isNotNull);
      expect(rule!.nextDueDate, startDate);
      expect(rule.isActive, isTrue);

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'recurring_rule');
      expect(outbox.single.op, 'upsert');
      expect(syncTriggerCount, 1);
    },
  );

  test('update enqueues another outbox upsert', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      kind: TxnKind.expense,
      title: 'Netflix',
      amountPaise: 49900,
      frequency: RecurFrequency.monthly,
      startDate: DateTime.utc(2026, 10, 5),
    );
    final rule = (await repo.findById(id))!;

    await repo.update(rule.copyWith(amountPaise: 59900));

    final updated = await repo.findById(id);
    expect(updated!.amountPaise, 59900);
    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(2)); // create + update
  });

  test('delete soft-deletes the rule (already-posted transactions are '
      'untouched, per spec §11.8)', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      kind: TxnKind.expense,
      title: 'Netflix',
      amountPaise: 49900,
      frequency: RecurFrequency.monthly,
      startDate: DateTime.utc(2026, 10, 5),
    );

    await repo.delete(id);

    final rules = await repo.watchAll('h1').first;
    expect(rules, isEmpty); // filtered out as soft-deleted
    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox.where((e) => e.op == 'delete'), hasLength(1));
  });

  test('previewOccurrences matches the posting engine\'s own stepping', () {
    final preview = repo.previewOccurrences(
      from: DateTime.utc(2026, 1, 31),
      frequency: RecurFrequency.monthly,
      intervalN: 1,
      dayOfMonth: 31,
      count: 3,
    );
    expect(preview, [
      DateTime.utc(2026, 1, 31),
      DateTime.utc(2026, 2, 28), // clamped
      DateTime.utc(2026, 3, 31),
    ]);
  });

  test(
    'postPending delegates to the posting engine and triggers a sync',
    () async {
      final id = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        kind: TxnKind.expense,
        title: 'Netflix',
        amountPaise: 49900,
        frequency: RecurFrequency.monthly,
        startDate: DateTime.utc(2026, 1, 1),
      );
      syncTriggerCount = 0;

      await repo.postPending(id);

      final expenses = await db.expenseDao.watchAll('h1').first;
      expect(expenses, hasLength(1));
      expect(syncTriggerCount, 1);
    },
  );

  test('skipPending advances next_due_date without posting', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      kind: TxnKind.expense,
      title: 'Netflix',
      amountPaise: 49900,
      frequency: RecurFrequency.monthly,
      startDate: DateTime.utc(2026, 1, 1),
    );
    syncTriggerCount = 0;

    await repo.skipPending(id);

    final expenses = await db.expenseDao.watchAll('h1').first;
    expect(expenses, isEmpty);
    final rule = await repo.findById(id);
    expect(rule!.nextDueDate, DateTime.utc(2026, 2, 1));
    expect(syncTriggerCount, 1);
  });
}
