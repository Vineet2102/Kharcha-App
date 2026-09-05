import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/budget.dart' as domain;
import '../../../domain/models/enums.dart';

extension BudgetRowMapper on Budget {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix).
  domain.Budget toDomain() => domain.Budget(
    id: id,
    householdId: householdId,
    scope: BudgetScope.values.byName(scope),
    userId: userId,
    categoryId: categoryId,
    amountPaise: amountPaise,
    periodMonth: periodMonth.toUtc(),
    isRollover: isRollover,
    alertThresholdPct: alertThresholdPct,
    createdBy: createdBy,
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    deletedAt: deletedAt?.toUtc(),
  );
}

extension BudgetDomainMapper on domain.Budget {
  BudgetsCompanion toCompanion({bool dirty = false, String? baseUpdatedAt}) =>
      BudgetsCompanion(
        id: Value(id),
        householdId: Value(householdId),
        scope: Value(scope.name),
        userId: Value(userId),
        categoryId: Value(categoryId),
        amountPaise: Value(amountPaise),
        periodMonth: Value(periodMonth),
        isRollover: Value(isRollover),
        alertThresholdPct: Value(alertThresholdPct),
        createdBy: Value(createdBy),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
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
