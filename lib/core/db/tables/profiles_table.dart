import 'package:drift/drift.dart';

class Profiles extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get displayName => text()();
  TextColumn get role => text().withDefault(const Constant('member'))();
  TextColumn get colourHex => text().withDefault(const Constant('#6750A4'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// When this member joined their current household (spec F-16's "joined
  /// date"). Null for a member with no household yet, or for pre-M2 rows
  /// pulled before this column existed. Server-managed only — every write
  /// path (create/join/leave/remove) goes through an RPC (§6.9.2), never a
  /// direct client write, so this is never stamped locally.
  DateTimeColumn get joinedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  /// Compare-and-swap base for push (spec §13 Test 5 / D12) — see the
  /// identical column on `categories_table.dart` for the full rationale.
  TextColumn get baseUpdatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
