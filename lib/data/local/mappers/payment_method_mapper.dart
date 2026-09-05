import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/payment_method.dart' as domain;

extension PaymentMethodRowMapper on PaymentMethod {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix).
  domain.PaymentMethod toDomain() => domain.PaymentMethod(
    id: id,
    householdId: householdId,
    name: name,
    type: PayMethodType.values.byName(type),
    isArchived: isArchived,
    sortOrder: sortOrder,
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    deletedAt: deletedAt?.toUtc(),
  );
}

extension PaymentMethodDomainMapper on domain.PaymentMethod {
  PaymentMethodsCompanion toCompanion({
    bool dirty = false,
    String? baseUpdatedAt,
  }) => PaymentMethodsCompanion(
    id: Value(id),
    householdId: Value(householdId),
    name: Value(name),
    type: Value(type.name),
    isArchived: Value(isArchived),
    sortOrder: Value(sortOrder),
    createdAt: Value(createdAt),
    updatedAt: Value(updatedAt),
    deletedAt: Value(deletedAt),
    isDirty: Value(dirty),
    localUpdatedAt: dirty ? Value(DateTime.now().toUtc()) : const Value.absent(),
    syncStatus: Value(dirty ? 'pending' : 'synced'),
    baseUpdatedAt: baseUpdatedAt == null
        ? const Value.absent()
        : Value(baseUpdatedAt),
  );
}
