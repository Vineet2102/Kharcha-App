import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/categories_table.dart';

part 'category_dao.g.dart';

@DriftAccessor(tables: [Categories])
class CategoryDao extends DatabaseAccessor<AppDatabase>
    with _$CategoryDaoMixin {
  CategoryDao(super.db);

  Stream<List<Category>> watchAll(String householdId) {
    return (select(categories)
          ..where(
            (t) => t.householdId.equals(householdId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<Category?> findById(String id) =>
      (select(categories)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(CategoriesCompanion entry) =>
      into(categories).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(categories)..where((t) => t.id.equals(id))).write(
        const CategoriesCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  /// Like [markSynced], but also stamps the compare-and-swap base to
  /// [baseUpdatedAt] (the value this device just successfully pushed) —
  /// used by `pushUpsert`'s conflict-resolution path (see docs/DECISIONS.md,
  /// Gate 4 2026-09-05 fix).
  Future<void> markSyncedWithBase(String id, String baseUpdatedAt) =>
      (update(categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(
          isDirty: const Value(false),
          syncStatus: const Value('synced'),
          baseUpdatedAt: Value(baseUpdatedAt),
        ),
      );

  /// Refreshes the compare-and-swap base to the server's current value
  /// without touching `isDirty`/`updatedAt` — used when a push conflict is
  /// resolved in favour of the (still-pending) local edit, so the next push
  /// attempt's compare-and-swap uses the up-to-date base.
  Future<void> updateBaseUpdatedAt(String id, String baseUpdatedAt) =>
      (update(categories)..where((t) => t.id.equals(id))).write(
        CategoriesCompanion(baseUpdatedAt: Value(baseUpdatedAt)),
      );

  Future<int> hardDelete(String id) =>
      (delete(categories)..where((t) => t.id.equals(id))).go();
}
