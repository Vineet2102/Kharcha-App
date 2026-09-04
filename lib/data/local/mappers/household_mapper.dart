import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/household.dart' as domain;

extension HouseholdRowMapper on Household {
  domain.Household toDomain() => domain.Household(
        id: id,
        name: name,
        currencyCode: currencyCode,
        timezone: timezone,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

extension HouseholdDomainMapper on domain.Household {
  HouseholdsCompanion toCompanion({bool dirty = false}) => HouseholdsCompanion(
        id: Value(id),
        name: Value(name),
        currencyCode: Value(currencyCode),
        timezone: Value(timezone),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        isDirty: Value(dirty),
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
