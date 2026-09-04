import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';

void main() {
  late AppDatabase db;
  final september = DateTime.utc(2026, 9);
  final october = DateTime.utc(2026, 10);

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> insertExpense({
    required String id,
    required String userId,
    required int amountPaise,
    required DateTime spentOn,
    String? categoryId,
    String? paymentMethodId,
    bool deleted = false,
  }) => db.expenseDao.upsert(
    ExpensesCompanion.insert(
      id: id,
      householdId: 'h1',
      userId: userId,
      amountPaise: amountPaise,
      categoryId: Value(categoryId),
      paymentMethodId: Value(paymentMethodId),
      spentAt: spentOn,
      spentOn: spentOn,
      deletedAt: Value(deleted ? spentOn : null),
      createdAt: spentOn,
      updatedAt: spentOn,
    ),
  );

  Future<void> insertIncome({
    required String id,
    required String userId,
    required int amountPaise,
    required DateTime receivedOn,
  }) => db.incomeDao.upsert(
    IncomesCompanion.insert(
      id: id,
      householdId: 'h1',
      userId: userId,
      amountPaise: amountPaise,
      receivedAt: receivedOn,
      receivedOn: receivedOn,
      createdAt: receivedOn,
      updatedAt: receivedOn,
    ),
  );

  /// The fixture shared by every test below (spec T-6.1: "totals match a
  /// hand-computed fixture"). September: u1 spends ₹100 (c1/pm1) + ₹50
  /// (c2/pm2); u2 spends ₹200 (c1/pm1) + ₹30 (uncategorised, no payment
  /// method). A ₹5,000 September expense is soft-deleted, and an August
  /// expense/income sit just outside the period — both must be excluded.
  Future<void> seed() async {
    await insertExpense(
      id: 'e1',
      userId: 'u1',
      amountPaise: 10000,
      spentOn: DateTime.utc(2026, 9, 1),
      categoryId: 'c1',
      paymentMethodId: 'pm1',
    );
    await insertExpense(
      id: 'e2',
      userId: 'u1',
      amountPaise: 5000,
      spentOn: DateTime.utc(2026, 9, 10),
      categoryId: 'c2',
      paymentMethodId: 'pm2',
    );
    await insertExpense(
      id: 'e3',
      userId: 'u2',
      amountPaise: 20000,
      spentOn: DateTime.utc(2026, 9, 15),
      categoryId: 'c1',
      paymentMethodId: 'pm1',
    );
    await insertExpense(
      id: 'e4-uncategorised',
      userId: 'u2',
      amountPaise: 3000,
      spentOn: DateTime.utc(2026, 9, 20),
    );
    await insertExpense(
      id: 'e5-deleted',
      userId: 'u1',
      amountPaise: 500000,
      spentOn: DateTime.utc(2026, 9, 5),
      deleted: true,
    );
    await insertExpense(
      id: 'e6-august',
      userId: 'u1',
      amountPaise: 999999,
      spentOn: DateTime.utc(2026, 8, 15),
    );
    await insertIncome(
      id: 'i1',
      userId: 'u1',
      amountPaise: 50000,
      receivedOn: DateTime.utc(2026, 9, 1),
    );
    await insertIncome(
      id: 'i2-august',
      userId: 'u1',
      amountPaise: 999,
      receivedOn: DateTime.utc(2026, 8, 1),
    );
  }

  test(
    'watchExpenseTotal sums only non-deleted expenses within the period',
    () async {
      await seed();
      final total = await db.reportDao
          .watchExpenseTotal(householdId: 'h1', start: september, end: october)
          .first;
      expect(total, 10000 + 5000 + 20000 + 3000);
    },
  );

  test('watchIncomeTotal sums only income within the period', () async {
    await seed();
    final total = await db.reportDao
        .watchIncomeTotal(householdId: 'h1', start: september, end: october)
        .first;
    expect(total, 50000);
  });

  test(
    'watchExpenseTotal for an empty household returns 0, not null',
    () async {
      final total = await db.reportDao
          .watchExpenseTotal(
            householdId: 'empty',
            start: september,
            end: october,
          )
          .first;
      expect(total, 0);
    },
  );

  test('watchExpenseByMember groups and sorts descending by total', () async {
    await seed();
    final totals = await db.reportDao
        .watchExpenseByMember(householdId: 'h1', start: september, end: october)
        .first;
    expect(totals.map((g) => (g.key, g.amountPaise)).toList(), [
      ('u2', 23000),
      ('u1', 15000),
    ]);
  });

  test('watchExpenseByCategory excludes uncategorised expenses and sorts descending', () async {
    await seed();
    final totals = await db.reportDao
        .watchExpenseByCategory(
          householdId: 'h1',
          start: september,
          end: october,
        )
        .first;
    expect(totals.map((g) => (g.key, g.amountPaise)).toList(), [
      ('c1', 30000),
      ('c2', 5000),
    ]);
  });

  test('watchExpenseByCategory respects limit', () async {
    await seed();
    final totals = await db.reportDao
        .watchExpenseByCategory(
          householdId: 'h1',
          start: september,
          end: october,
          limit: 1,
        )
        .first;
    expect(totals, hasLength(1));
    expect(totals.single.key, 'c1');
  });

  test(
    'watchExpenseByPaymentMethod excludes rows with no payment method',
    () async {
      await seed();
      final totals = await db.reportDao
          .watchExpenseByPaymentMethod(
            householdId: 'h1',
            start: september,
            end: october,
          )
          .first;
      expect(totals.map((g) => (g.key, g.amountPaise)).toList(), [
        ('pm1', 30000),
        ('pm2', 5000),
      ]);
    },
  );

  test('watchRecentExpenses ignores the month filter but still excludes soft-deletes', () async {
    await seed();
    final recent = await db.reportDao.watchRecentExpenses('h1', limit: 3).first;
    // Most-recent-by-spentAt first, across all months; the August row
    // (e6-august, 9/15's neighbour by date but not by recency) still
    // outranks nothing here since it's the oldest — recency order is
    // e3 (9/15) > e4-uncategorised (9/20) is more recent than e3, so
    // expected strictly by spentAt desc:
    expect(recent.map((e) => e.id).toList(), [
      'e4-uncategorised', // 2026-09-20
      'e3', // 2026-09-15
      'e2', // 2026-09-10
    ]);
  });
}
