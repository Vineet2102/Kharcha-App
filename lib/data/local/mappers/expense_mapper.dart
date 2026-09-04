import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/expense.dart' as domain;

extension ExpenseRowMapper on Expense {
  domain.Expense toDomain() => domain.Expense(
        id: id,
        householdId: householdId,
        userId: userId,
        amountPaise: amountPaise,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        spentAt: spentAt,
        spentOn: spentOn,
        note: note,
        merchant: merchant,
        hasReceipt: hasReceipt,
        recurringRuleId: recurringRuleId,
        occurrenceDate: occurrenceDate,
        createdByDevice: createdByDevice,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );
}

extension ExpenseDomainMapper on domain.Expense {
  ExpensesCompanion toCompanion({bool dirty = false}) => ExpensesCompanion(
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
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
