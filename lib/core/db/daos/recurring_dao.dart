import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/recurring_rules_table.dart';

part 'recurring_dao.g.dart';

@DriftAccessor(tables: [RecurringRules])
class RecurringDao extends DatabaseAccessor<AppDatabase>
    with _$RecurringDaoMixin {
  RecurringDao(super.db);

  Stream<List<RecurringRule>> watchAll(String householdId) {
    return (select(recurringRules)..where(
          (t) => t.householdId.equals(householdId) & t.deletedAt.isNull(),
        ))
        .watch();
  }

  Future<List<RecurringRule>> dueOn(String householdId, DateTime asOf) {
    return (select(recurringRules)..where(
          (t) =>
              t.householdId.equals(householdId) &
              t.isActive.equals(true) &
              t.deletedAt.isNull() &
              t.nextDueDate.isSmallerOrEqualValue(asOf),
        ))
        .get();
  }

  Future<RecurringRule?> findById(String id) =>
      (select(recurringRules)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(RecurringRulesCompanion entry) =>
      into(recurringRules).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(recurringRules)..where((t) => t.id.equals(id))).write(
        RecurringRulesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(recurringRules)..where((t) => t.id.equals(id))).write(
        const RecurringRulesCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  Future<int> hardDelete(String id) =>
      (delete(recurringRules)..where((t) => t.id.equals(id))).go();
}
