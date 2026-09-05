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

  /// Compare-and-swap push (spec §13 Test 5 / D12, see docs/DECISIONS.md's
  /// Gate 4 2026-09-05 fix): succeeds unconditionally when [expectedBase] is
  /// null (no confirmed server row yet — a plain create), otherwise only
  /// when the row's current `updated_at` still equals [expectedBase].
  /// Returns whether the write actually happened — `false` means someone
  /// else moved the row since, a genuine conflict for the caller to resolve.
  Future<bool> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    DateTime? expectedBase,
  ) async {
    if (expectedBase == null) {
      await _client.from(table).upsert(payload, onConflict: 'id');
      return true;
    }
    final updated = await _client
        .from(table)
        .update(payload)
        .eq('id', payload['id'] as String)
        .eq('updated_at', expectedBase.toIso8601String())
        .select('id');
    return (updated as List).isNotEmpty;
  }

  /// The current server row for [id], or null if it no longer exists
  /// (already hard-deleted, or never created) — used to resolve a push-time
  /// conflict from [upsertIfBaseMatches].
  Future<Map<String, dynamic>?> fetchById(String id) async {
    final rows = await _client.from(table).select().eq('id', id).limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    return list.isEmpty ? null : list.first;
  }

  Future<void> softDelete(String id, DateTime now) => _client
      .from(table)
      .update({
        'deleted_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      })
      .eq('id', id);
}
