import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/budget.dart' as domain;
import '../../../domain/models/enums.dart';

extension BudgetRowMapper on Budget {
  domain.Budget toDomain() => domain.Budget(
        id: id,
        householdId: householdId,
        scope: BudgetScope.values.byName(scope),
        userId: userId,
        categoryId: categoryId,
        amountPaise: amountPaise,
        periodMonth: periodMonth,
        isRollover: isRollover,
        alertThresholdPct: alertThresholdPct,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );
}

extension BudgetDomainMapper on domain.Budget {
  BudgetsCompanion toCompanion({bool dirty = false}) => BudgetsCompanion(
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
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
