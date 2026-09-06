import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/domain/models/expense_filter.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('insert then read an expense back', () async {
    final now = DateTime.utc(2026, 9, 1, 10, 0);
    await db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: 'e1',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 15000,
        spentAt: now,
        spentOn: DateTime.utc(2026, 9, 1),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final row = await db.expenseDao.findById('e1');
    expect(row, isNotNull);
    expect(row!.amountPaise, 15000);
    expect(row.householdId, 'h1');
  });

  test(
    'watchAll excludes soft-deleted rows and orders by spentOn desc',
    () async {
      final now = DateTime.utc(2026, 9, 1);
      Future<void> insert(String id, DateTime spentOn) => db.expenseDao.upsert(
        ExpensesCompanion.insert(
          id: id,
          householdId: 'h1',
          userId: 'u1',
          amountPaise: 1000,
          spentAt: spentOn,
          spentOn: spentOn,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await insert('e1', DateTime.utc(2026, 9, 1));
      await insert('e2', DateTime.utc(2026, 9, 5));
      await insert('e3', DateTime.utc(2026, 9, 3));

      await db.expenseDao.softDelete('e2', now);

      final rows = await db.expenseDao.watchAll('h1').first;
      expect(rows.map((e) => e.id).toList(), ['e3', 'e1']);
    },
  );

  test('softDelete marks the row dirty and pending', () async {
    final now = DateTime.utc(2026, 9, 1);
    await db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: 'e1',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 1000,
        spentAt: now,
        spentOn: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await db.expenseDao.softDelete('e1', now);

    final row = await db.expenseDao.findById('e1');
    expect(row!.deletedAt, isNotNull);
    expect(row.isDirty, isTrue);
    expect(row.syncStatus, 'pending');
  });

  test('getFiltered returns every matching row unpaginated, for the Export screen (T-12.1)', () async {
    final now = DateTime.utc(2026, 9, 1);
    Future<void> insert(
      String id,
      String userId,
      String? categoryId,
      DateTime spentOn,
    ) => db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: id,
        householdId: 'h1',
        userId: userId,
        categoryId: Value(categoryId),
        amountPaise: 1000,
        spentAt: spentOn,
        spentOn: spentOn,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await insert('e1', 'u1', 'c1', DateTime.utc(2026, 9, 1));
    await insert('e2', 'u2', 'c1', DateTime.utc(2026, 9, 5));
    await insert('e3', 'u1', 'c2', DateTime.utc(2026, 9, 10));
    await db.expenseDao.softDelete('e3', now);

    final rows = await db.expenseDao.getFiltered(
      householdId: 'h1',
      filter: const ExpenseFilter(memberIds: ['u1']),
    );

    // e3 is soft-deleted and e2 belongs to a different member — only e1
    // should survive the filter, unbounded by any page-size limit.
    expect(rows.map((r) => r.id).toList(), ['e1']);
  });

  group('hasAnyOn', () {
    test(
      'true when a non-deleted expense was logged on that calendar date',
      () async {
        final now = DateTime.utc(2026, 9, 6);
        await db.expenseDao.upsert(
          ExpensesCompanion.insert(
            id: 'e1',
            householdId: 'h1',
            userId: 'u1',
            amountPaise: 1000,
            spentAt: now,
            spentOn: now,
            createdAt: now,
            updatedAt: now,
          ),
        );

        expect(
          await db.expenseDao.hasAnyOn('h1', DateTime.utc(2026, 9, 6)),
          isTrue,
        );
      },
    );

    test(
      'false for a different date, another household, or a soft-deleted row',
      () async {
        final now = DateTime.utc(2026, 9, 6);
        await db.expenseDao.upsert(
          ExpensesCompanion.insert(
            id: 'e1',
            householdId: 'h1',
            userId: 'u1',
            amountPaise: 1000,
            spentAt: now,
            spentOn: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.expenseDao.upsert(
          ExpensesCompanion.insert(
            id: 'e2',
            householdId: 'h2',
            userId: 'u1',
            amountPaise: 1000,
            spentAt: now,
            spentOn: now,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await db.expenseDao.softDelete('e1', now);

        expect(
          await db.expenseDao.hasAnyOn('h1', DateTime.utc(2026, 9, 5)),
          isFalse,
        );
        expect(
          await db.expenseDao.hasAnyOn('h2', DateTime.utc(2026, 9, 6)),
          isTrue,
        );
        expect(
          await db.expenseDao.hasAnyOn('h1', DateTime.utc(2026, 9, 6)),
          isFalse,
        );
      },
    );
  });
}
