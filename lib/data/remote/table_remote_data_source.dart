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
  /// Returns the row's actual `updated_at` after a successful write, or
  /// `null` if someone else moved the row since — a genuine conflict for the
  /// caller to resolve.
  ///
  /// Deliberately returns the *server's* resulting `updated_at`, not the
  /// payload's claimed one: `touch_updated_at()` does
  /// `GREATEST(now(), incoming)`, so after any offline stretch the server
  /// silently advances the timestamp past what the client sent. A caller
  /// that trusted the payload's value instead (as this used to) would record
  /// the wrong "known-good base" for its next push — and a second edit to
  /// the same row still queued in the same drain pass would then spuriously
  /// CAS-mismatch against the real server value and get discarded as if it
  /// were a genuine remote conflict. See docs/DECISIONS.md, Gate 10.
  Future<DateTime?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    DateTime? expectedBase,
  ) async {
    if (expectedBase == null) {
      final rows = await _client
          .from(table)
          .upsert(payload, onConflict: 'id')
          .select('updated_at');
      return _serverUpdatedAt(rows);
    }
    final updated = await _client
        .from(table)
        .update(payload)
        .eq('id', payload['id'] as String)
        .eq('updated_at', expectedBase.toIso8601String())
        .select('updated_at');
    return _serverUpdatedAt(updated);
  }

  DateTime? _serverUpdatedAt(dynamic rows) {
    final list = List<Map<String, dynamic>>.from(rows as List);
    if (list.isEmpty) return null;
    return DateTime.parse(list.first['updated_at'] as String).toUtc();
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
