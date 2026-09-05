import 'package:drift/drift.dart';

class Attachments extends Table {
  TextColumn get id => text()();
  TextColumn get householdId => text()();
  TextColumn get expenseId => text()();
  TextColumn get storagePath => text()();
  TextColumn get mimeType => text().withDefault(const Constant('image/jpeg'))();
  IntColumn get sizeBytes => integer().withDefault(const Constant(0))();
  IntColumn get widthPx => integer().nullable()();
  IntColumn get heightPx => integer().nullable()();
  TextColumn get uploadedBy => text()();
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
