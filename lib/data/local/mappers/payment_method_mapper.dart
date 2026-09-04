import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/payment_method.dart' as domain;

extension PaymentMethodRowMapper on PaymentMethod {
  domain.PaymentMethod toDomain() => domain.PaymentMethod(
    id: id,
    householdId: householdId,
    name: name,
    type: PayMethodType.values.byName(type),
    isArchived: isArchived,
    sortOrder: sortOrder,
    createdAt: createdAt,
    updatedAt: updatedAt,
    deletedAt: deletedAt,
  );
}

extension PaymentMethodDomainMapper on domain.PaymentMethod {
  PaymentMethodsCompanion toCompanion({bool dirty = false}) =>
      PaymentMethodsCompanion(
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
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
