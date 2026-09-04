import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import 'entity_sync_adapters.dart';

part 'pull_service.g.dart';

/// Pull side of the sync engine (spec §9.6 pullChanges(), T-4.4): pages
/// every entity's since-cursor changes down into the local mirror, in
/// dependency order, advancing each entity's `sync_meta` cursor as it goes.
class PullService {
  PullService({required this.db, required this.adapters});

  final AppDatabase db;
  final List<EntitySyncAdapter> adapters;

  static const pageLimit = 500;

  /// The 5s overlap absorbs clock skew between devices; re-applying an
  /// already-synced row is harmless because `pullApply` upserts are
  /// idempotent (spec §9.6).
  static const overlap = Duration(seconds: 5);

  Future<void> pullAll(String householdId) async {
    for (final adapter in adapters) {
      await _pullEntity(adapter, householdId);
    }
  }

  /// Pulls a single entity — used by the Realtime listener (T-4.8), which
  /// only knows which table changed, not the whole household's state.
  Future<void> pullEntity(String entityKey, String householdId) async {
    for (final adapter in adapters) {
      if (adapter.entityKey == entityKey) {
        await _pullEntity(adapter, householdId);
        return;
      }
    }
  }

  Future<void> _pullEntity(
    EntitySyncAdapter adapter,
    String householdId,
  ) async {
    final meta = await db.syncMetaDao.find(adapter.entityKey);
    // Drift returns DateTime columns flagged as local time even though the
    // stored instant is correct (`local.toUtc() == theInstantThatWasWritten`)
    // — normalise before `.toIso8601String()` is used for a wire query,
    // otherwise it would render without the 'Z' offset.
    var cursor = (meta?.lastPulledAt?.toUtc() ?? DateTime.utc(1970)).subtract(
      overlap,
    );
    DateTime? maxSeen;

    while (true) {
      final rows = await adapter.selectSince(
        householdId: householdId,
        cursor: cursor,
        limit: pageLimit,
      );
      for (final row in rows) {
        await adapter.pullApply(db, row);
        final updatedAt = DateTime.parse(row['updated_at'] as String).toUtc();
        if (maxSeen == null || updatedAt.isAfter(maxSeen)) maxSeen = updatedAt;
      }
      if (rows.length < pageLimit) break;
      cursor = maxSeen!;
    }

    await db.syncMetaDao.upsert(
      SyncMetaCompanion(
        entity: Value(adapter.entityKey),
        lastPulledAt: Value(maxSeen ?? meta?.lastPulledAt),
        lastSuccessAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

@Riverpod(keepAlive: true)
PullService pullService(Ref ref) => PullService(
  db: ref.watch(appDatabaseProvider),
  adapters: ref.watch(entitySyncAdaptersProvider),
);
