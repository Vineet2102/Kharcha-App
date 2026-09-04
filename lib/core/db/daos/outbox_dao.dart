import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/outbox_entries_table.dart';

part 'outbox_dao.g.dart';

@DriftAccessor(tables: [OutboxEntries])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(super.db);

  Future<void> enqueue(OutboxEntriesCompanion entry) => into(outboxEntries).insert(entry);

  /// Entries ready to be pushed, ordered FIFO (spec §9.6 pushOutbox()).
  Future<List<OutboxEntry>> dueEntries(DateTime now) {
    return (select(outboxEntries)
          ..where((t) => t.nextAttemptAt.isNull() | t.nextAttemptAt.isSmallerOrEqualValue(now))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Stream<int> watchPendingCount() {
    final query = selectOnly(outboxEntries)..addColumns([outboxEntries.id.count()]);
    return query.map((row) => row.read(outboxEntries.id.count()) ?? 0).watchSingle();
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

  Future<int> remove(String id) => (delete(outboxEntries)..where((t) => t.id.equals(id))).go();
}
