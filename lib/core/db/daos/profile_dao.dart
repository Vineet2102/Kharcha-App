import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/profiles_table.dart';

part 'profile_dao.g.dart';

@DriftAccessor(tables: [Profiles])
class ProfileDao extends DatabaseAccessor<AppDatabase> with _$ProfileDaoMixin {
  ProfileDao(super.db);

  Stream<Profile?> watchById(String id) =>
      (select(profiles)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<Profile?> findById(String id) =>
      (select(profiles)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(ProfilesCompanion entry) =>
      into(profiles).insertOnConflictUpdate(entry);
}
