import 'package:drift/drift.dart';

class RecurringRules extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get userId => text()();
  TextColumn get kind => text().withDefault(const Constant('expense'))();
  TextColumn get title => text()();
  IntColumn get amountPaise => integer()();
  TextColumn get categoryId => text().nullable()();
  TextColumn get paymentMethodId => text().nullable()();
  TextColumn get note => text().withDefault(const Constant(''))();
  TextColumn get frequency => text()();
  IntColumn get intervalN => integer().withDefault(const Constant(1))();
  IntColumn get dayOfMonth => integer().nullable()();
  IntColumn get weekday => integer().nullable()();
  IntColumn get monthOfYear => integer().nullable()();
  DateTimeColumn get startDate => dateTime()();
  DateTimeColumn get endDate => dateTime().nullable()();
  DateTimeColumn get nextDueDate => dateTime()();
  BoolColumn get autoPost => boolean().withDefault(const Constant(false))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get lastPostedOn => dateTime().nullable()();
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
