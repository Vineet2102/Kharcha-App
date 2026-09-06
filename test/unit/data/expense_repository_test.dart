import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/repositories/expense_repository.dart';
import 'package:kharcha/domain/models/expense_filter.dart';

void main() {
  late AppDatabase db;
  late int syncTriggerCount;
  late ExpenseRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncTriggerCount = 0;
    repo = ExpenseRepository(db, () => syncTriggerCount++);
  });
  tearDown(() => db.close());

  test(
    'create writes the row to Drift and enqueues an outbox upsert',
    () async {
      final id = await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 5000,
        categoryId: 'c1',
        spentAt: DateTime.utc(2026, 9, 4, 12),
      );

      final row = await db.expenseDao.findById(id);
      expect(row, isNotNull);
      expect(row!.amountPaise, 5000);
      expect(row.isDirty, isTrue);
      expect(row.syncStatus, 'pending');
      // spentOn is derived from spentAt via AppTime.calendarDate (IST). Drift
      // decodes the stored instant with isUtc: false (docs/DECISIONS.md), so
      // compare instants via .toUtc() rather than raw DateTime equality.
      expect(row.spentOn.toUtc(), DateTime.utc(2026, 9, 4));

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'expense');
      expect(outbox.single.op, 'upsert');
      expect(outbox.single.entityId, id);
      expect(syncTriggerCount, 1);
    },
  );

  test('delete soft-deletes and enqueues an outbox delete', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 1000,
      spentAt: DateTime.utc(2026, 9, 4),
    );
    await db.outboxDao.remove(
      (await db.outboxDao.dueEntries(DateTime.now().toUtc())).single.id,
    );

    await repo.delete(id);

    final row = await db.expenseDao.findById(id);
    expect(row!.deletedAt, isNotNull);
    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
    expect(outbox.single.op, 'delete');
  });

  test('undoCreate before the create is pushed removes the outbox entry '
      'entirely — no delete is ever sent to the server', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 1000,
      spentAt: DateTime.utc(2026, 9, 4),
    );

    await repo.undoCreate(id);

    final row = await db.expenseDao.findById(id);
    expect(row!.deletedAt, isNotNull, reason: 'still soft-deleted locally');
    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(
      outbox,
      isEmpty,
      reason: 'the create was never pushed, so no delete is needed either',
    );
  });

  test('undoCreate after the create has already been pushed enqueues a real '
      'delete so the undo still propagates', () async {
    final id = await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 1000,
      spentAt: DateTime.utc(2026, 9, 4),
    );
    // Simulate the OutboxProcessor having already pushed + removed the
    // create's upsert entry before Undo is tapped.
    await db.outboxDao.remove(
      (await db.outboxDao.dueEntries(DateTime.now().toUtc())).single.id,
    );

    await repo.undoCreate(id);

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
    expect(outbox.single.op, 'delete');
    expect(outbox.single.entityId, id);
  });

  test(
    'hasPossibleDuplicate finds a same amount/category row within 2 minutes',
    () async {
      await repo.create(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 5000,
        categoryId: 'c1',
        spentAt: DateTime.utc(2026, 9, 4, 12, 0),
      );

      final duplicate = await repo.hasPossibleDuplicate(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 5000,
        categoryId: 'c1',
        spentAt: DateTime.utc(2026, 9, 4, 12, 1, 30),
      );
      expect(duplicate, isTrue);

      final differentAmount = await repo.hasPossibleDuplicate(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 6000,
        categoryId: 'c1',
        spentAt: DateTime.utc(2026, 9, 4, 12, 1, 30),
      );
      expect(differentAmount, isFalse);

      final outsideWindow = await repo.hasPossibleDuplicate(
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 5000,
        categoryId: 'c1',
        spentAt: DateTime.utc(2026, 9, 4, 12, 5),
      );
      expect(outsideWindow, isFalse);
    },
  );

  test('watchFiltered applies category and search filters', () async {
    await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 1000,
      categoryId: 'groceries',
      note: 'Milk and bread',
      spentAt: DateTime.utc(2026, 9, 1),
    );
    await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 2000,
      categoryId: 'transport',
      note: 'Auto fare',
      spentAt: DateTime.utc(2026, 9, 2),
    );

    final byCategory = await repo
        .watchFiltered(
          householdId: 'h1',
          filter: const ExpenseFilter(categoryIds: ['groceries']),
          limit: 50,
        )
        .first;
    expect(byCategory, hasLength(1));
    expect(byCategory.single.categoryId, 'groceries');

    final bySearch = await repo
        .watchFiltered(
          householdId: 'h1',
          filter: const ExpenseFilter(searchText: 'auto'),
          limit: 50,
        )
        .first;
    expect(bySearch, hasLength(1));
    expect(bySearch.single.note, 'Auto fare');
  });

  test('watchFilteredTotal sums only the matching rows', () async {
    await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 1000,
      categoryId: 'groceries',
      spentAt: DateTime.utc(2026, 9, 1),
    );
    await repo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 2500,
      categoryId: 'transport',
      spentAt: DateTime.utc(2026, 9, 2),
    );

    final total = await repo
        .watchFilteredTotal(householdId: 'h1', filter: const ExpenseFilter())
        .first;
    expect(total, 3500);

    final groceriesOnly = await repo
        .watchFilteredTotal(
          householdId: 'h1',
          filter: const ExpenseFilter(categoryIds: ['groceries']),
        )
        .first;
    expect(groceriesOnly, 1000);
  });
}
