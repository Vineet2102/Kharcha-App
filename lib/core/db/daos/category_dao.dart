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

  Future<int> hardDelete(String id) =>
      (delete(categories)..where((t) => t.id.equals(id))).go();
}
