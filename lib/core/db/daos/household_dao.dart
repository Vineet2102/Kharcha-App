import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/households_table.dart';

part 'household_dao.g.dart';

@DriftAccessor(tables: [Households])
class HouseholdDao extends DatabaseAccessor<AppDatabase>
    with _$HouseholdDaoMixin {
  HouseholdDao(super.db);

  Future<Household?> findById(String id) =>
      (select(households)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(HouseholdsCompanion entry) =>
      into(households).insertOnConflictUpdate(entry);
}
