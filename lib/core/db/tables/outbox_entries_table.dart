import 'package:drift/drift.dart';

/// Queue of local mutations waiting to be pushed to Supabase (spec §9.5).
class OutboxEntries extends Table {
  TextColumn get id => text()();
  TextColumn get entity => text()(); // 'expense' | 'income' | ...
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // 'upsert' | 'delete' | 'upload'
  TextColumn get payload => text()(); // JSON
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();

  /// 'pending' (still eligible for auto-retry) | 'failed' (permanent failure
  /// — RLS denial, constraint violation — surfaced in Settings, never
  /// auto-retried; spec §9.6 pushOutbox()). Added in schema v2.
  TextColumn get status => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};
}
