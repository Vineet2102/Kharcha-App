import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/profiles_table.dart';

part 'profile_dao.g.dart';

@DriftAccessor(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<AppDatabase> with _$ProfileDaoMixin {
  ProfileDao(super.db);

  Stream<Profile?> watchById(String id) =>
      (select(profiles)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// Every member of the household, active first then by name — the "Paid
  /// by" selector (spec §11.2) and the Expense List's member filter/name
  /// chip (spec §11.3).
  Stream<List<Profile>> watchAll(String householdId) {
    return (select(profiles)
          ..where((t) => t.householdId.equals(householdId))
          ..orderBy([
            (t) => OrderingTerm.desc(t.isActive),
            (t) => OrderingTerm.asc(t.displayName),
          ]))
        .watch();
  }

  Future<Profile?> findById(String id) =>
      (select(profiles)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(ProfilesCompanion entry) =>
      into(profiles).insertOnConflictUpdate(entry);
}
