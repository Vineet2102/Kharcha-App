import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/profile.dart' as domain;

extension ProfileRowMapper on Profile {
  domain.Profile toDomain() => domain.Profile(
        id: id,
        householdId: householdId,
        displayName: displayName,
        role: MemberRole.values.byName(role),
        colourHex: colourHex,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}

extension ProfileDomainMapper on domain.Profile {
  ProfilesCompanion toCompanion({bool dirty = false}) => ProfilesCompanion(
        id: Value(id),
        householdId: Value(householdId),
        displayName: Value(displayName),
        role: Value(role.name),
        colourHex: Value(colourHex),
        isActive: Value(isActive),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        isDirty: Value(dirty),
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
