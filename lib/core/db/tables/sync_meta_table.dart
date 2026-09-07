import 'package:drift/drift.dart';

/// Per-table incremental pull cursors (spec §9.5).
class SyncMeta extends Table {
  TextColumn get entity => text()();
  DateTimeColumn get lastPulledAt => dateTime().nullable()();
  DateTimeColumn get lastSuccessAt => dateTime().nullable()();

  /// Which household these cursors were last pulled for (spec §9.6 rule 3,
  /// T-M2.7/T-M2.14). Stamped on every successful pull; compared against the
  /// signed-in member's current household at the start of the next cycle —
  /// a mismatch (joined, left, or switched households) means the rows this
  /// device already has no longer belong to it, so the whole local database
  /// is wiped and refetched rather than incrementally reconciled.
  TextColumn get householdId => text().nullable()();

  @override
  Set<Column> get primaryKey => {entity};
}
