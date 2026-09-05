import 'package:drift/drift.dart';

class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get name => text()();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
  TextColumn get iconKey => text().withDefault(const Constant('category'))();
  TextColumn get colourHex => text().withDefault(const Constant('#607D8B'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(100))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  /// The row's `updated_at` as of the last time this device confirmed it
  /// matched the server (a pull, or this device's own successful push) —
  /// the compare-and-swap base for the next push (spec §13 Test 5 / D12).
  /// Null means "no confirmed server state yet" (a locally-created row).
  ///
  /// Stored as the server's raw ISO-8601 string, verbatim — never parsed
  /// into a `DateTime` and reformatted. Postgres's `timestamptz` has
  /// microsecond precision; a `DateTimeColumn` here would silently round
  /// to whole seconds on every write, so a push's `.eq('updated_at', ...)`
  /// compare-and-swap would almost never match once a row needed a real
  /// conflict retry (see docs/DECISIONS.md, Gate 10 2026-09-05 fix — this
  /// column was a lossy `DateTimeColumn` before schema v4).
  TextColumn get baseUpdatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
