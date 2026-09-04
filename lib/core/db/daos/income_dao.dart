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
}
