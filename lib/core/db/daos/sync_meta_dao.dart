import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sync_meta_table.dart';

part 'sync_meta_dao.g.dart';

@DriftAccessor(tables: [SyncMeta])
class SyncMetaDao extends DatabaseAccessor<AppDatabase>
    with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  Future<SyncMetaData?> find(String entity) => (select(
    syncMeta,
  )..where((t) => t.entity.equals(entity))).getSingleOrNull();

  Future<void> upsert(SyncMetaCompanion entry) =>
      into(syncMeta).insertOnConflictUpdate(entry);

  /// The household id this device's cursors were last pulled for, or null
  /// if nothing has ever been pulled (fresh install, or just wiped). Every
  /// row stamped in a given cycle carries the same household id, so any one
  /// non-null value is representative (spec §9.6 rule 3, T-M2.7).
  Future<String?> anyStoredHouseholdId() async {
    final row =
        await (select(syncMeta)
              ..where((t) => t.householdId.isNotNull())
              ..limit(1))
            .getSingleOrNull();
    return row?.householdId;
  }
}
