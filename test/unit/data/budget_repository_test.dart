import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/errors/failure.dart';
import 'package:kharcha/data/repositories/budget_repository.dart';
import 'package:kharcha/domain/models/enums.dart';

void main() {
  late AppDatabase db;
  late int syncTriggerCount;
  late BudgetRepository repo;

  final september = DateTime.utc(2026, 9, 1);
  final october = DateTime.utc(2026, 10, 1);

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    syncTriggerCount = 0;
    repo = BudgetRepository(db, () => syncTriggerCount++);
  });
  tearDown(() => db.close());

  test(
    'create writes a household budget and enqueues an outbox upsert',
    () async {
      final result = await repo.create(
        householdId: 'h1',
        scope: BudgetScope.household,
        amountPaise: 500000,
        periodMonth: september,
        createdBy: 'admin1',
      );

      expect(result.isOk, isTrue);
      final budgets = await repo.watchForMonth('h1', september).first;
      expect(budgets, hasLength(1));
      expect(budgets.single.scope, BudgetScope.household);
      expect(budgets.single.amountPaise, 500000);

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'budget');
      expect(outbox.single.op, 'upsert');
      expect(syncTriggerCount, 1);
    },
  );

  test('create rejects an invalid scope shape client-side (T-8.1)', () async {
    final result = await repo.create(
      householdId: 'h1',
      scope: BudgetScope.household,
      userId: 'u1', // household must not carry a member
      amountPaise: 500000,
      periodMonth: september,
      createdBy: 'admin1',
    );

    expect(result.isErr, isTrue);
    expect(result.failureOrNull, isA<ValidationFailure>());
    final budgets = await repo.watchForMonth('h1', september).first;
    expect(budgets, isEmpty);
  });

  test('update rejects an invalid scope shape client-side', () async {
    final created = await repo.create(
      householdId: 'h1',
      scope: BudgetScope.category,
      categoryId: 'c1',
      amountPaise: 100000,
      periodMonth: september,
      createdBy: 'admin1',
    );
    final budget = (await repo.findById(created.valueOrNull!))!;

    final result = await repo.update(
      budget.copyWith(scope: BudgetScope.user, categoryId: 'c1', userId: null),
    );

    expect(result.isErr, isTrue);
    expect(result.failureOrNull, isA<ValidationFailure>());
  });

  test('delete soft-deletes and enqueues an outbox delete', () async {
    final created = await repo.create(
      householdId: 'h1',
      scope: BudgetScope.household,
      amountPaise: 100000,
      periodMonth: september,
      createdBy: 'admin1',
    );
    final id = created.valueOrNull!;
    await db.outboxDao.remove(
      (await db.outboxDao.dueEntries(DateTime.now().toUtc())).single.id,
    );

    await repo.delete(id);

    final row = await db.budgetDao.findById(id);
    expect(row!.deletedAt, isNotNull);
    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
    expect(outbox.single.op, 'delete');
  });

  group('watchSpent (T-8.1 scope filtering)', () {
    Future<void> insertExpense({
      required String id,
      required String userId,
      required int amountPaise,
      String? categoryId,
      required DateTime spentOn,
    }) => db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: id,
        householdId: 'h1',
        userId: userId,
        amountPaise: amountPaise,
        categoryId: Value(categoryId),
        spentAt: spentOn,
        spentOn: spentOn,
        createdAt: spentOn,
        updatedAt: spentOn,
      ),
    );

    test('a category budget only counts spend in that category', () async {
      await insertExpense(
        id: 'e1',
        userId: 'u1',
        amountPaise: 10000,
        categoryId: 'c1',
        spentOn: september,
      );
      await insertExpense(
        id: 'e2',
        userId: 'u2',
        amountPaise: 20000,
        categoryId: 'c2',
        spentOn: september,
      );
      final created = await repo.create(
        householdId: 'h1',
        scope: BudgetScope.category,
        categoryId: 'c1',
        amountPaise: 100000,
        periodMonth: september,
        createdBy: 'admin1',
      );
      final budget = (await repo.findById(created.valueOrNull!))!;

      final spent = await repo.spentOnce(budget);
      expect(spent, 10000);
    });
  });

  group('copyToNext12Months (T-8.2)', () {
    test(
      'creates exactly 12 rows when none of the months already have one',
      () async {
        final created = await repo.create(
          householdId: 'h1',
          scope: BudgetScope.household,
          amountPaise: 500000,
          periodMonth: september,
          createdBy: 'admin1',
        );
        final source = (await repo.findById(created.valueOrNull!))!;

        final count = await repo.copyToNext12Months(source);

        expect(count, 12);
        final octoberBudgets = await repo.watchForMonth('h1', october).first;
        expect(octoberBudgets, hasLength(1));
        expect(octoberBudgets.single.amountPaise, 500000);
        final nextSeptember = await repo
            .watchForMonth('h1', DateTime.utc(2027, 9, 1))
            .first;
        expect(nextSeptember, hasLength(1));
      },
    );

    test(
      'skips a month that already has a budget with the same scope',
      () async {
        final created = await repo.create(
          householdId: 'h1',
          scope: BudgetScope.household,
          amountPaise: 500000,
          periodMonth: september,
          createdBy: 'admin1',
        );
        final source = (await repo.findById(created.valueOrNull!))!;
        await repo.create(
          householdId: 'h1',
          scope: BudgetScope.household,
          amountPaise: 999,
          periodMonth: october,
          createdBy: 'admin1',
        );

        final count = await repo.copyToNext12Months(source);

        expect(count, 11);
        final octoberBudgets = await repo.watchForMonth('h1', october).first;
        expect(
          octoberBudgets.single.amountPaise,
          999,
          reason: 'pre-existing budget untouched',
        );
      },
    );
  });
}
