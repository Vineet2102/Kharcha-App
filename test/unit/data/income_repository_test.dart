import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/repositories/income_repository.dart';

void main() {
  late AppDatabase db;
  late int syncTriggerCount;
  late IncomeRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncTriggerCount = 0;
    repo = IncomeRepository(db, () => syncTriggerCount++);
  });
  tearDown(() => db.close());

  test(
    'create writes the row to Drift and enqueues an outbox upsert',
    () async {
      final id = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 50000,
        categoryId: 'c1',
        receivedAt: DateTime.utc(2026, 9, 4, 12),
        source: 'Employer Pvt Ltd',
      );

      final row = await db.incomeDao.findById(id);
      expect(row, isNotNull);
      expect(row!.amountPaise, 50000);
      expect(row.source, 'Employer Pvt Ltd');
      expect(row.isDirty, isTrue);
      expect(row.syncStatus, 'pending');
      // receivedOn is derived from receivedAt via AppTime.calendarDate (IST).
      // Drift decodes the stored instant with isUtc: false (docs/DECISIONS.md),
      // so compare instants via .toUtc() rather than raw DateTime equality.
      expect(row.receivedOn.toUtc(), DateTime.utc(2026, 9, 4));

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'income');
      expect(outbox.single.op, 'upsert');
      expect(outbox.single.entityId, id);
      expect(syncTriggerCount, 1);
    },
  );

  test(
    'update re-derives receivedOn and re-enqueues an outbox upsert',
    () async {
      final id = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 1000,
        receivedAt: DateTime.utc(2026, 9, 1),
      );
      final existing = (await repo.findById(id))!;

      await repo.update(
        existing.copyWith(
          amountPaise: 2000,
          receivedAt: DateTime.utc(2026, 9, 3, 10),
        ),
      );

      final row = await db.incomeDao.findById(id);
      expect(row!.amountPaise, 2000);
      expect(row.receivedOn.toUtc(), DateTime.utc(2026, 9, 3));
    },
  );

  test('delete soft-deletes and enqueues an outbox delete', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 1000,
      receivedAt: DateTime.utc(2026, 9, 4),
    );
    await db.outboxDao.remove(
      (await db.outboxDao.dueEntries(DateTime.now().toUtc())).single.id,
    );

    await repo.delete(id);

    final row = await db.incomeDao.findById(id);
    expect(row!.deletedAt, isNotNull);
    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
    expect(outbox.single.op, 'delete');
  });

  test(
    'watchAll excludes soft-deleted rows and orders most-recent first',
    () async {
      final older = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 1000,
        receivedAt: DateTime.utc(2026, 9, 1),
      );
      final newer = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 2000,
        receivedAt: DateTime.utc(2026, 9, 3),
      );
      final deleted = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 3000,
        receivedAt: DateTime.utc(2026, 9, 5),
      );
      await repo.delete(deleted);

      final all = await repo.watchAll('h1').first;
      expect(all.map((i) => i.id).toList(), [newer, older]);
    },
  );
}
