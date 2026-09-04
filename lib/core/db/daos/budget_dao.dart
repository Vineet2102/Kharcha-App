import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/budgets_table.dart';

part 'budget_dao.g.dart';

@DriftAccessor(tables: [Budgets])
class BudgetDao extends DatabaseAccessor<AppDatabase> with _$BudgetDaoMixin {
  BudgetDao(super.db);

  Stream<List<Budget>> watchForMonth(String householdId, DateTime periodMonth) {
    return (select(budgets)..where(
          (t) =>
              t.householdId.equals(householdId) &
              t.periodMonth.equals(periodMonth) &
              t.deletedAt.isNull(),
        ))
        .watch();
  }

  Future<Budget?> findById(String id) =>
      (select(budgets)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Looks up the one budget (if any) matching a scope shape exactly — the
  /// same key the DB's `budgets_unique_scope` index enforces. Used for the
  /// previous month's rollover lookup and to skip an already-existing month
  /// when "copy to next 12 months" runs (T-8.2/T-8.3).
  Future<Budget?> findByScope({
    required String householdId,
    required DateTime periodMonth,
    required String scope,
    String? userId,
    String? categoryId,
  }) {
    return (select(budgets)..where((t) {
          var cond =
              t.householdId.equals(householdId) &
              t.periodMonth.equals(periodMonth) &
              t.scope.equals(scope) &
              t.deletedAt.isNull();
          cond =
              cond &
              (userId == null ? t.userId.isNull() : t.userId.equals(userId));
          cond =
              cond &
              (categoryId == null
                  ? t.categoryId.isNull()
                  : t.categoryId.equals(categoryId));
          return cond;
        }))
        .getSingleOrNull();
  }

  Future<void> upsert(BudgetsCompanion entry) =>
      into(budgets).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(budgets)..where((t) => t.id.equals(id))).write(
        BudgetsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(budgets)..where((t) => t.id.equals(id))).write(
        const BudgetsCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(budgets)..where((t) => t.id.equals(id))).go();
}
