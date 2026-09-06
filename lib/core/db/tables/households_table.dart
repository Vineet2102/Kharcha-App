import 'package:drift/drift.dart';

class Households extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get currencyCode => text().withDefault(const Constant('INR'))();
  TextColumn get timezone =>
      text().withDefault(const Constant('Asia/Kolkata'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  // Local sync bookkeeping (spec §9.5) — not present server-side.
  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  /// Compare-and-swap base for push (spec §13 Test 5 / D12) — see the
  /// identical column on `categories_table.dart` for the full rationale.
  TextColumn get baseUpdatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
