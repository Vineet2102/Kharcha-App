import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/incomes_table.dart';

part 'income_dao.g.dart';

@DriftAccessor(tables: [Incomes])
class IncomeDao extends DatabaseAccessor<AppDatabase> with _$IncomeDaoMixin {
  IncomeDao(super.db);

  Stream<List<Income>> watchAll(String householdId) {
    return (select(incomes)
          ..where(
            (t) => t.householdId.equals(householdId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.receivedOn)]))
        .watch();
  }

  Future<Income?> findById(String id) =>
      (select(incomes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Income?> watchById(String id) =>
      (select(incomes)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsert(IncomesCompanion entry) =>
      into(incomes).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(incomes)..where((t) => t.id.equals(id))).write(
        IncomesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(incomes)..where((t) => t.id.equals(id))).write(
        const IncomesCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(incomes)..where((t) => t.id.equals(id))).go();

  /// Used by the category delete guard (spec §11.5) alongside
  /// `ExpenseDao.countByCategory`: a non-deleted income still referencing the
  /// id blocks a hard/soft delete in favour of "Archive instead".
  Future<int> countByCategory(String categoryId) async {
    final query = selectOnly(incomes)
      ..addColumns([incomes.id.count()])
      ..where(incomes.categoryId.equals(categoryId) & incomes.deletedAt.isNull());
    final row = await query.getSingle();
    return row.read(incomes.id.count()) ?? 0;
  }
}
