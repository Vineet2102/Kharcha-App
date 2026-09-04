import 'package:drift/drift.dart';

class Expenses extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get userId => text()();
  IntColumn get amountPaise => integer()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get paymentMethodId => text().nullable()();
  DateTimeColumn get spentAt => dateTime()();
  DateTimeColumn get spentOn => dateTime()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get merchant => text().withDefault(const Constant(''))();
  BoolColumn get hasReceipt => boolean().withDefault(const Constant(false))();
  TextColumn get recurringRuleId => text().nullable()();
  DateTimeColumn get occurrenceDate => dateTime().nullable()();
  TextColumn get createdByDevice => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
