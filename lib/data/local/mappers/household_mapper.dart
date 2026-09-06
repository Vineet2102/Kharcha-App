import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/household.dart' as domain;

extension HouseholdRowMapper on Household {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix).
  domain.Household toDomain() => domain.Household(
    id: id,
    name: name,
    currencyCode: currencyCode,
    timezone: timezone,
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
  );
}

extension HouseholdDomainMapper on domain.Household {
  HouseholdsCompanion toCompanion({
    bool dirty = false,
    String? baseUpdatedAt,
  }) => HouseholdsCompanion(
    id: Value(id),
    name: Value(name),
    currencyCode: Value(currencyCode),
    timezone: Value(timezone),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    isDirty: Value(dirty),
    localUpdatedAt: dirty
        ? Value(DateTime.now().toUtc())
        : const Value.absent(),
    syncStatus: Value(dirty ? 'pending' : 'synced'),
    baseUpdatedAt: baseUpdatedAt == null
        ? const Value.absent()
        : Value(baseUpdatedAt),
  );
}
