import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/expense.dart' as domain;

extension ExpenseRowMapper on Expense {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix) — left
  /// uncorrected here, editing an existing expense would silently push its
  /// timestamps to the server 5:30 off (IST).
  domain.Expense toDomain() => domain.Expense(
    id: id,
    householdId: householdId,
    userId: userId,
    amountPaise: amountPaise,
    categoryId: categoryId,
    paymentMethodId: paymentMethodId,
    spentAt: spentAt.toUtc(),
    spentOn: spentOn.toUtc(),
    note: note,
    merchant: merchant,
    hasReceipt: hasReceipt,
    recurringRuleId: recurringRuleId,
    occurrenceDate: occurrenceDate?.toUtc(),
    createdByDevice: createdByDevice,
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    deletedAt: deletedAt?.toUtc(),
    isDirty: isDirty,
  );
}

extension ExpenseDomainMapper on domain.Expense {
  ExpensesCompanion toCompanion({
    bool dirty = false,
    DateTime? baseUpdatedAt,
  }) => ExpensesCompanion(
    id: Value(id),
    householdId: Value(householdId),
    userId: Value(userId),
    amountPaise: Value(amountPaise),
    categoryId: Value(categoryId),
    paymentMethodId: Value(paymentMethodId),
    spentAt: Value(spentAt),
    spentOn: Value(spentOn),
    note: Value(note),
    merchant: Value(merchant),
    hasReceipt: Value(hasReceipt),
    recurringRuleId: Value(recurringRuleId),
    occurrenceDate: Value(occurrenceDate),
    createdByDevice: Value(createdByDevice),
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
