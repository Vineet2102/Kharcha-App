import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/outbox_entries_table.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [OutboxEntries])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  Future<void> enqueue(OutboxEntriesCompanion entry) =>
      into(outboxEntries).insert(entry);

  /// Entries still eligible for auto-retry and ready to be pushed, ordered
  /// FIFO (spec §9.6 pushOutbox()). Permanently-failed entries (`status ==
  /// 'failed'`) are excluded — they wait for manual attention, not a timer.
  Future<List<OutboxEntry>> dueEntries(DateTime now) {
    return (select(outboxEntries)
          ..where(
            (t) =>
                t.status.equals('pending') &
                (t.nextAttemptAt.isNull() |
                    t.nextAttemptAt.isSmallerOrEqualValue(now)),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  /// Every pending entry regardless of `next_attempt_at`, used to compute the
  /// "N changes waiting" count shown while offline (spec §9.6 `SyncOffline`).
  Stream<int> watchPendingCount() {
    final query = selectOnly(outboxEntries)
      ..addColumns([outboxEntries.id.count()])
      ..where(outboxEntries.status.equals('pending'));
    return query
        .map((row) => row.read(outboxEntries.id.count()) ?? 0)
        .watchSingle();
  }

  /// One-off count for [SyncEngine]'s `SyncOffline`/`SyncError` payloads —
  /// `watchPendingCount()` is a stream, which is the wrong shape there.
  Future<int> pendingCount() async {
    final query = selectOnly(outboxEntries)
      ..addColumns([outboxEntries.id.count()])
      ..where(outboxEntries.status.equals('pending'));
    final row = await query.getSingle();
    return row.read(outboxEntries.id.count()) ?? 0;
  }

  /// True once at least one pending entry has failed 5+ times — spec §9.6:
  /// "Give up surfacing errors to the user until attempts >= 5", so a single
  /// transient blip doesn't alarm anyone.
  Future<bool> hasStuckEntries() async {
    final query = selectOnly(outboxEntries)
      ..addColumns([outboxEntries.id.count()])
      ..where(
        outboxEntries.status.equals('pending') &
            outboxEntries.attempts.isBiggerOrEqualValue(5),
      );
    final row = await query.getSingle();
    return (row.read(outboxEntries.id.count()) ?? 0) > 0;
  }

  Stream<int> watchFailedCount() {
    final query = selectOnly(outboxEntries)
      ..addColumns([outboxEntries.id.count()])
      ..where(outboxEntries.status.equals('failed'));
    return query
        .map((row) => row.read(outboxEntries.id.count()) ?? 0)
        .watchSingle();
  }

  Future<void> recordAttempt(
    String id, {
    required int attempts,
    String? error,
    DateTime? nextAttemptAt,
  }) {
    return (update(outboxEntries)..where((t) => t.id.equals(id))).write(
      OutboxEntriesCompanion(
        attempts: Value(attempts),
        lastError: Value(error),
        nextAttemptAt: Value(nextAttemptAt),
      ),
    );
  }

  /// Marks an entry as permanently failed (spec §9.6: RLS denial, constraint
  /// violation) — kept for visibility in Settings → Sync issues, never
  /// auto-retried again.
  Future<void> markFailed(String id, String error) {
    return (update(outboxEntries)..where((t) => t.id.equals(id))).write(
      OutboxEntriesCompanion(
        status: const Value('failed'),
        lastError: Value(error),
      ),
    );
  }

  Future<int> remove(String id) =>
      (delete(outboxEntries)..where((t) => t.id.equals(id))).go();
}
