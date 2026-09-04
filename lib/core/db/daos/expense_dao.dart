import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/expenses_table.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Stream<List<Expense>> watchAll(String householdId) {
    return (select(expenses)
          ..where((t) => t.householdId.equals(householdId) & t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.spentOn)]))
        .watch();
  }

  Future<Expense?> findById(String id) => (select(expenses)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(ExpensesCompanion entry) => into(expenses).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) => (update(expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) => (update(expenses)..where((t) => t.id.equals(id))).write(
        const ExpensesCompanion(isDirty: Value(false), syncStatus: Value('synced')),
      );

  Future<int> hardDelete(String id) => (delete(expenses)..where((t) => t.id.equals(id))).go();
}
