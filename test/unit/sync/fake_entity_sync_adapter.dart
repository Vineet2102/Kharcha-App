import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/sync/entity_sync_adapters.dart';

/// A scriptable [EntitySyncAdapter] test double — records every call it
/// receives and can be told to throw on the next `pushUpsert`, so
/// [OutboxProcessor] can be exercised without mocking Supabase's Postgrest
/// builder chain.
class FakeEntitySyncAdapter extends EntitySyncAdapter {
  FakeEntitySyncAdapter(this.entityKey, {List<String>? callLog})
    : callLog = callLog ?? [];

  @override
  final String entityKey;

  /// Shared across every fake in a test so ordering can be asserted.
  final List<String> callLog;

  final List<Map<String, dynamic>> upserts = [];
  final List<String> deletes = [];
  final List<String> syncedIds = [];

  Object? errorToThrow;

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) async => const [];

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {}

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) async {
    callLog.add('$entityKey:upsert:${payload['id']}');
    if (errorToThrow != null) throw errorToThrow!;
    upserts.add(payload);
  }

  @override
  Future<void> pushSoftDelete(String id, DateTime now) async {
    callLog.add('$entityKey:delete:$id');
    if (errorToThrow != null) throw errorToThrow!;
    deletes.add(id);
  }

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) async {
    syncedIds.add(id);
  }
}
