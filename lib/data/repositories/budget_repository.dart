import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/budget.dart' as domain;
import '../../domain/models/budget_status.dart';
import '../../domain/models/enums.dart';
import '../local/mappers/budget_mapper.dart';
import '../sync/sync_engine.dart';
import 'profile_repository.dart';

part 'budget_repository.g.dart';

const _uuid = Uuid();

/// Budget CRUD + local status computation (spec §11.7, T-8.1/T-8.3):
/// local-first read, every write goes to Drift + the outbox per the iron
/// rule (§9.1). RLS (`bud_write`: admin, or the member the budget targets)
/// is the real enforcement — [create]/[update] only check the scope *shape*
/// client-side, mirroring the DB's `budgets_scope_shape` constraint so a bad
/// request never round-trips to Postgres to be told no.
class BudgetRepository {
  BudgetRepository(this._db, this._triggerSync);

  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<List<domain.Budget>> watchForMonth(
    String householdId,
    DateTime periodMonth,
  ) => _db.budgetDao
      .watchForMonth(householdId, periodMonth)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Future<domain.Budget?> findById(String id) async =>
      (await _db.budgetDao.findById(id))?.toDomain();

  Future<domain.Budget?> findByScope({
    required String householdId,
    required DateTime periodMonth,
    required BudgetScope scope,
    String? userId,
    String? categoryId,
  }) async => (await _db.budgetDao.findByScope(
    householdId: householdId,
    periodMonth: periodMonth,
    scope: scope.name,
    userId: userId,
    categoryId: categoryId,
  ))?.toDomain();

  /// Live spend for [budget]'s own month, filtered to its scope.
  Stream<int> watchSpent(domain.Budget budget) =>
      _db.reportDao.watchExpenseForScope(
        householdId: budget.householdId,
        start: budget.periodMonth,
        end: AppTime.monthAfter(budget.periodMonth, 1),
        userId: _scopeUserId(budget),
        categoryId: _scopeCategoryId(budget),
      );

  /// One-shot spend, for rollover math and alert evaluation — neither needs
  /// a live subscription.
  Future<int> spentOnce(domain.Budget budget) => watchSpent(budget).first;

  /// Live, fully-computed status for one budget: spend + (if rollover is
  /// on) the previous month's carry-over, recombined on every new spend
  /// figure. The previous month's own numbers are read once per
  /// recombination rather than subscribed to — they essentially never
  /// change once the month is over, so this trades a rare missed live
  /// update for not having to fan out a second live subscription per row.
  Stream<BudgetStatus> watchStatus(domain.Budget budget) =>
      watchSpent(budget).asyncMap((spent) async {
        final rollover = await _computeRollover(budget);
        return BudgetStatus(
          budget: budget,
          spentPaise: spent,
          rolloverPaise: rollover,
        );
      });

  Future<int> _computeRollover(domain.Budget budget) async {
    if (!budget.isRollover) return 0;
    final previousMonth = AppTime.monthAfter(budget.periodMonth, -1);
    final previousBudget = await findByScope(
      householdId: budget.householdId,
      periodMonth: previousMonth,
      scope: budget.scope,
      userId: budget.userId,
      categoryId: budget.categoryId,
    );
    if (previousBudget == null) return 0;
    final previousSpent = await spentOnce(previousBudget);
    return computeRolloverPaise(
      isRollover: true,
      previousBudgetAmountPaise: previousBudget.amountPaise,
      previousSpentPaise: previousSpent,
    );
  }

  String? _scopeUserId(domain.Budget b) =>
      (b.scope == BudgetScope.user || b.scope == BudgetScope.userCategory)
      ? b.userId
      : null;

  String? _scopeCategoryId(domain.Budget b) =>
      (b.scope == BudgetScope.category || b.scope == BudgetScope.userCategory)
      ? b.categoryId
      : null;

  Future<Result<String, Failure>> create({
    required String householdId,
    required BudgetScope scope,
    String? userId,
    String? categoryId,
    required int amountPaise,
    required DateTime periodMonth,
    bool isRollover = false,
    int alertThresholdPct = 80,
    required String createdBy,
  }) async {
    if (!domain.isValidBudgetScopeShape(scope, userId, categoryId)) {
      return const Result.err(
        ValidationFailure(
          'That combination of scope, member, and category '
          'is not allowed.',
        ),
      );
    }
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _save(
      domain.Budget(
        id: id,
        householdId: householdId,
        scope: scope,
        userId: userId,
        categoryId: categoryId,
        amountPaise: amountPaise,
        periodMonth: periodMonth,
        isRollover: isRollover,
        alertThresholdPct: alertThresholdPct,
        createdBy: createdBy,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return Result.ok(id);
  }

  Future<Result<void, Failure>> update(domain.Budget budget) async {
    if (!domain.isValidBudgetScopeShape(
      budget.scope,
      budget.userId,
      budget.categoryId,
    )) {
      return const Result.err(
        ValidationFailure(
          'That combination of scope, member, and category '
          'is not allowed.',
        ),
      );
    }
    await _save(budget.copyWith(updatedAt: DateTime.now().toUtc()));
    return const Result.ok(null);
  }

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await _db.budgetDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'budget',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    _triggerSync();
  }

  /// "Copy to next 12 months" (T-8.2): creates one row per of the next 12
  /// months with [source]'s scope/amount/rollover/threshold, skipping any
  /// month that already has a budget with this exact scope shape (the
  /// unique index would reject the duplicate anyway). Returns the number of
  /// rows actually created.
  Future<int> copyToNext12Months(domain.Budget source) async {
    var created = 0;
    for (var i = 1; i <= 12; i++) {
      final month = AppTime.monthAfter(source.periodMonth, i);
      final existing = await findByScope(
        householdId: source.householdId,
        periodMonth: month,
        scope: source.scope,
        userId: source.userId,
        categoryId: source.categoryId,
      );
      if (existing != null) continue;
      final result = await create(
        householdId: source.householdId,
        scope: source.scope,
        userId: source.userId,
        categoryId: source.categoryId,
        amountPaise: source.amountPaise,
        periodMonth: month,
        isRollover: source.isRollover,
        alertThresholdPct: source.alertThresholdPct,
        createdBy: source.createdBy,
      );
      if (result.isOk) created++;
    }
    return created;
  }

  Future<void> _save(domain.Budget budget) async {
    await _db.budgetDao.upsert(budget.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'budget',
        entityId: budget.id,
        op: 'upsert',
        payload: jsonEncode(budget.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
BudgetRepository budgetRepository(Ref ref) => BudgetRepository(
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);

/// This month's (or any given month's) budgets — the Budgets screen and the
/// Dashboard's budget card (T-8.2/T-8.4).
@riverpod
Stream<List<domain.Budget>> budgetsForMonth(Ref ref, DateTime periodMonth) {
  final householdId = ref.watch(currentHouseholdIdProvider);
  if (householdId == null) return Stream.value(const []);
  return ref
      .watch(budgetRepositoryProvider)
      .watchForMonth(householdId, periodMonth);
}
