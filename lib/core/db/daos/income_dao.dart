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

  /// Every row matching the given scope, unpaginated — the Export screen
  /// (spec §11.11, T-12.1). Deliberately plain named params rather than a
  /// dedicated filter model: income has no payment-method/amount-range/
  /// search dimensions worth generalising for, unlike `ExpenseFilter`.
  Future<List<Income>> getFiltered({
    required String householdId,
    DateTime? startDate,
    DateTime? endDate,
    List<String> memberIds = const [],
    List<String> categoryIds = const [],
  }) {
    return (select(incomes)
          ..where((t) {
            Expression<bool> cond =
                t.householdId.equals(householdId) & t.deletedAt.isNull();
            if (startDate != null) {
              cond = cond & t.receivedOn.isBiggerOrEqualValue(startDate);
            }
            if (endDate != null) {
              cond = cond & t.receivedOn.isSmallerOrEqualValue(endDate);
            }
            if (memberIds.isNotEmpty) cond = cond & t.userId.isIn(memberIds);
            if (categoryIds.isNotEmpty) {
              cond = cond & t.categoryId.isIn(categoryIds);
            }
            return cond;
          })
          ..orderBy([(t) => OrderingTerm.desc(t.receivedOn)]))
        .get();
  }

  /// The already-posted income for one recurring occurrence, if any — see
  /// `ExpenseDao.findByOccurrence`.
  Future<Income?> findByOccurrence(
    String recurringRuleId,
    DateTime occurrenceDate,
  ) =>
      (select(incomes)..where(
            (t) =>
                t.recurringRuleId.equals(recurringRuleId) &
                t.occurrenceDate.equals(occurrenceDate) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

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

  /// See `CategoryDao.markSyncedWithBase`.
  Future<void> markSyncedWithBase(String id, String baseUpdatedAt) =>
      (update(incomes)..where((t) => t.id.equals(id))).write(
        IncomesCompanion(
          isDirty: const Value(false),
          syncStatus: const Value('synced'),
          baseUpdatedAt: Value(baseUpdatedAt),
        ),
      );

  /// See `CategoryDao.updateBaseUpdatedAt`.
  Future<void> updateBaseUpdatedAt(String id, String baseUpdatedAt) =>
      (update(incomes)..where((t) => t.id.equals(id))).write(
        IncomesCompanion(baseUpdatedAt: Value(baseUpdatedAt)),
      );

  Future<int> hardDelete(String id) =>
      (delete(incomes)..where((t) => t.id.equals(id))).go();

  /// Used by the category delete guard (spec §11.5) alongside
  /// `ExpenseDao.countByCategory`: a non-deleted income still referencing the
  /// id blocks a hard/soft delete in favour of "Archive instead".
  Future<int> countByCategory(String categoryId) async {
    final query = selectOnly(incomes)
      ..addColumns([incomes.id.count()])
      ..where(
        incomes.categoryId.equals(categoryId) & incomes.deletedAt.isNull(),
      );
    final row = await query.getSingle();
    return row.read(incomes.id.count()) ?? 0;
  }
}
