import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/profile.dart' as domain;

extension ProfileRowMapper on Profile {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix).
  domain.Profile toDomain() => domain.Profile(
    id: id,
    householdId: householdId,
    displayName: displayName,
    role: MemberRole.values.byName(role),
    colourHex: colourHex,
    isActive: isActive,
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
  );
}

extension ProfileDomainMapper on domain.Profile {
  ProfilesCompanion toCompanion({bool dirty = false, String? baseUpdatedAt}) =>
      ProfilesCompanion(
        id: Value(id),
        householdId: Value(householdId),
        displayName: Value(displayName),
        role: Value(role.name),
        colourHex: Value(colourHex),
        isActive: Value(isActive),
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
