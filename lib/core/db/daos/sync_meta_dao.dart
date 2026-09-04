import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/sync_meta_table.dart';

part 'sync_meta_dao.g.dart';

@DriftAccessor(tables: [SyncMeta])
class SyncMetaDao extends DatabaseAccessor<AppDatabase> with _$SyncMetaDaoMixin {
  SyncMetaDao(super.db);

  Future<SyncMetaData?> find(String entity) =>
      (select(syncMeta)..where((t) => t.entity.equals(entity))).getSingleOrNull();

  Future<void> upsert(SyncMetaCompanion entry) => into(syncMeta).insertOnConflictUpdate(entry);
}
