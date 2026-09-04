import 'package:drift/drift.dart';

/// Per-table incremental pull cursors (spec §9.5).
class SyncMeta extends Table {
  TextColumn get entity => text()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {entity};
}
