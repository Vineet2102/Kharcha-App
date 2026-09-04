import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/recurring_rule.dart' as domain;

extension RecurringRuleRowMapper on RecurringRule {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix).
  domain.RecurringRule toDomain() => domain.RecurringRule(
    id: id,
    householdId: householdId,
    userId: userId,
    kind: TxnKind.values.byName(kind),
    title: title,
    amountPaise: amountPaise,
    categoryId: categoryId,
    paymentMethodId: paymentMethodId,
    note: note,
    frequency: RecurFrequency.values.byName(frequency),
    intervalN: intervalN,
    dayOfMonth: dayOfMonth,
    weekday: weekday,
    monthOfYear: monthOfYear,
    startDate: startDate.toUtc(),
    endDate: endDate?.toUtc(),
    nextDueDate: nextDueDate.toUtc(),
    autoPost: autoPost,
    isActive: isActive,
    lastPostedOn: lastPostedOn?.toUtc(),
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    deletedAt: deletedAt?.toUtc(),
  );
}

extension RecurringRuleDomainMapper on domain.RecurringRule {
  RecurringRulesCompanion toCompanion({bool dirty = false}) =>
      RecurringRulesCompanion(
        id: Value(id),
        householdId: Value(householdId),
        userId: Value(userId),
        kind: Value(kind.name),
        title: Value(title),
        amountPaise: Value(amountPaise),
        categoryId: Value(categoryId),
        paymentMethodId: Value(paymentMethodId),
        note: Value(note),
        frequency: Value(frequency.name),
        intervalN: Value(intervalN),
        dayOfMonth: Value(dayOfMonth),
        weekday: Value(weekday),
        monthOfYear: Value(monthOfYear),
        startDate: Value(startDate),
        endDate: Value(endDate),
        nextDueDate: Value(nextDueDate),
        autoPost: Value(autoPost),
        isActive: Value(isActive),
        lastPostedOn: Value(lastPostedOn),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
        isDirty: Value(dirty),
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
