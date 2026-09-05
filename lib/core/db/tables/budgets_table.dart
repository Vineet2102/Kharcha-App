import 'package:drift/drift.dart';

class Budgets extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get scope => text()();
  TextColumn get userId => text().nullable()();
  TextColumn get categoryId => text().nullable()();
  IntColumn get amountPaise => integer()();
  DateTimeColumn get periodMonth => dateTime()();
  BoolColumn get isRollover => boolean().withDefault(const Constant(false))();
  IntColumn get alertThresholdPct =>
      integer().withDefault(const Constant(80))();
  TextColumn get createdBy => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  /// See `Categories.baseUpdatedAt`.
  DateTimeColumn get baseUpdatedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
