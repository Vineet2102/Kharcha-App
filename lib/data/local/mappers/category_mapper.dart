import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';

extension CategoryRowMapper on Category {
  domain.Category toDomain() => domain.Category(
    id: id,
    householdId: householdId,
    name: name,
    kind: CategoryKind.values.byName(kind),
    iconKey: iconKey,
    colourHex: colourHex,
    sortOrder: sortOrder,
    isArchived: isArchived,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

extension CategoryDomainMapper on domain.Category {
  CategoriesCompanion toCompanion({bool dirty = false}) => CategoriesCompanion(
    id: Value(id),
    householdId: Value(householdId),
    name: Value(name),
    kind: Value(kind.name),
    iconKey: Value(iconKey),
    colourHex: Value(colourHex),
    sortOrder: Value(sortOrder),
    isArchived: Value(isArchived),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
    isDirty: Value(dirty),
    syncStatus: Value(dirty ? 'pending' : 'synced'),
  );
}
