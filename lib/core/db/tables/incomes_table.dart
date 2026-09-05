import 'package:drift/drift.dart';

class Incomes extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get userId => text()();
  IntColumn get amountPaise => integer()();
  TextColumn get categoryId => text().nullable()();
  DateTimeColumn get receivedAt => dateTime()();
  DateTimeColumn get receivedOn => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get source => text().withDefault(const Constant(''))();
  TextColumn get recurringRuleId => text().nullable()();
  DateTimeColumn get occurrenceDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  /// See `Categories.baseUpdatedAt`.
  TextColumn get baseUpdatedAt => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
