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
    String? merchant,
    bool deleted = false,
  }) => db.expenseDao.upsert(
    ExpensesCompanion.insert(
      id: id,
      householdId: 'h1',
      userId: userId,
      amountPaise: amountPaise,
      categoryId: Value(categoryId),
      paymentMethodId: Value(paymentMethodId),
      merchant: merchant == null ? const Value.absent() : Value(merchant),
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
      merchant: 'Reliance Fresh',
    );
    await insertExpense(
      id: 'e2',
      userId: 'u1',
      amountPaise: 5000,
      spentOn: DateTime.utc(2026, 9, 10),
      categoryId: 'c2',
      paymentMethodId: 'pm2',
      merchant: 'Cafe Coffee Day',
    );
    await insertExpense(
      id: 'e3',
      userId: 'u2',
      amountPaise: 20000,
      spentOn: DateTime.utc(2026, 9, 15),
      categoryId: 'c1',
      paymentMethodId: 'pm1',
      merchant: 'Reliance Fresh',
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

  group('watchExpenseForScope (T-8.1/T-8.3 budget scopes)', () {
    test('household scope (no filters) matches the plain total', () async {
      await seed();
      final total = await db.reportDao
          .watchExpenseForScope(
            householdId: 'h1',
            start: september,
            end: october,
          )
          .first;
      expect(total, 10000 + 5000 + 20000 + 3000);
    });

    test('user scope filters to one member', () async {
      await seed();
      final total = await db.reportDao
          .watchExpenseForScope(
            householdId: 'h1',
            start: september,
            end: october,
            userId: 'u2',
          )
          .first;
      expect(total, 20000 + 3000);
    });

    test('category scope filters to one category', () async {
      await seed();
      final total = await db.reportDao
          .watchExpenseForScope(
            householdId: 'h1',
            start: september,
            end: october,
            categoryId: 'c1',
          )
          .first;
      expect(total, 10000 + 20000);
    });

    test('userCategory scope filters to both', () async {
      await seed();
      final total = await db.reportDao
          .watchExpenseForScope(
            householdId: 'h1',
            start: september,
            end: october,
            userId: 'u1',
            categoryId: 'c1',
          )
          .first;
      expect(total, 10000);
    });
  });

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

  group('watchMonthlyTrend (T-11.1)', () {
    test('returns exactly [months] entries, zero-filled where there is no data', () async {
      await seed();
      final totals = await db.reportDao
          .watchMonthlyTrend(householdId: 'h1', endMonth: september, months: 12)
          .first;
      expect(totals, hasLength(12));
      expect(totals.first.month, DateTime.utc(2025, 10));
      expect(totals.last.month, september);
    });

    test('the current and previous month reconcile with the plain totals', () async {
      await seed();
      final totals = await db.reportDao
          .watchMonthlyTrend(householdId: 'h1', endMonth: september, months: 12)
          .first;
      final byMonth = {for (final t in totals) t.month: t};
      expect(byMonth[september]!.expensePaise, 10000 + 5000 + 20000 + 3000);
      expect(byMonth[september]!.incomePaise, 50000);
      expect(byMonth[DateTime.utc(2026, 8)]!.expensePaise, 999999);
      expect(byMonth[DateTime.utc(2026, 8)]!.incomePaise, 999);
    });

    test('a month with no rows at all is zero, not missing', () async {
      await seed();
      final totals = await db.reportDao
          .watchMonthlyTrend(householdId: 'h1', endMonth: september, months: 12)
          .first;
      final july = totals.firstWhere((t) => t.month == DateTime.utc(2026, 7));
      expect(july.expensePaise, 0);
      expect(july.incomePaise, 0);
    });
  });

  test(
    'watchMemberMonthlyTrend groups expense totals by month and member',
    () async {
      await seed();
      final totals = await db.reportDao
          .watchMemberMonthlyTrend(
            householdId: 'h1',
            endMonth: september,
            months: 2,
          )
          .first;
      expect(
        totals.map((t) => (t.month, t.userId, t.amountPaise)).toSet(),
        {
          (DateTime.utc(2026, 8), 'u1', 999999),
          (september, 'u1', 15000),
          (september, 'u2', 23000),
        },
      );
    },
  );

  test(
    'watchCategoryMonthlyTrend groups by month and category, excluding uncategorised',
    () async {
      await seed();
      final totals = await db.reportDao
          .watchCategoryMonthlyTrend(
            householdId: 'h1',
            endMonth: september,
            months: 1,
          )
          .first;
      expect(totals.map((t) => (t.month, t.categoryId, t.amountPaise)).toSet(), {
        (september, 'c1', 30000),
        (september, 'c2', 5000),
      });
    },
  );

  test(
    'watchExpenseByWeekday sums non-deleted expenses per calendar weekday',
    () async {
      await seed();
      final totals = await db.reportDao
          .watchExpenseByWeekday(
            householdId: 'h1',
            start: september,
            end: october,
          )
          .first;
      final byWeekday = {for (final t in totals) t.weekday: t.totalPaise};

      // Independently hand-computed from the seed's real calendar dates
      // (e5-deleted on 9/5 must not contribute to its weekday).
      final expected = <int, int>{};
      void add(DateTime d, int paise) =>
          expected[d.weekday] = (expected[d.weekday] ?? 0) + paise;
      add(DateTime.utc(2026, 9, 1), 10000);
      add(DateTime.utc(2026, 9, 10), 5000);
      add(DateTime.utc(2026, 9, 15), 20000);
      add(DateTime.utc(2026, 9, 20), 3000);
      expect(byWeekday, expected);
    },
  );

  test('watchTopMerchants groups by merchant, excluding blank merchants', () async {
    await seed();
    final totals = await db.reportDao
        .watchTopMerchants(householdId: 'h1', start: september, end: october)
        .first;
    expect(totals.map((g) => (g.key, g.amountPaise)).toList(), [
      ('Reliance Fresh', 30000),
      ('Cafe Coffee Day', 5000),
    ]);
  });

  test('watchTopMerchants respects limit', () async {
    await seed();
    final totals = await db.reportDao
        .watchTopMerchants(
          householdId: 'h1',
          start: september,
          end: october,
          limit: 1,
        )
        .first;
    expect(totals, hasLength(1));
    expect(totals.single.key, 'Reliance Fresh');
  });
}
