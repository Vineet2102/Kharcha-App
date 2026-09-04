import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared shape for every syncable table's remote access (spec §9.6
/// pushOutbox()/pullChanges()): select-since-cursor, upsert, soft-delete.
/// All 9 syncable tables use exactly this shape — parameterised only by
/// table name — so one implementation covers them all; see
/// `lib/data/sync/entity_sync_adapters.dart` for the per-entity glue that
/// bridges these raw JSON maps to typed Drift rows.
class TableRemoteDataSource {
  const TableRemoteDataSource(this._client, this.table);

  final SupabaseClient _client;
  final String table;

  /// Rows for [householdId] updated strictly after [cursor], oldest first,
  /// capped at [limit] (spec §9.6: page until fewer than 500 rows return).
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async {
    final rows = await _client
        .from(table)
        .select()
        .eq('household_id', householdId)
        .gt('updated_at', cursor.toIso8601String())
        .order('updated_at')
        .limit(limit);
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> upsert(Map<String, dynamic> payload) =>
      _client.from(table).upsert(payload, onConflict: 'id');

  Future<void> softDelete(String id, DateTime now) => _client
      .from(table)
      .update({
        'deleted_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      })
      .eq('id', id);
}
