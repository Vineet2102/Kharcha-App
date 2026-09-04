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

  TextColumn get syncStatus => text().withDefault(const Constant('synced'))();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  BoolColumn get isDirty => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}
