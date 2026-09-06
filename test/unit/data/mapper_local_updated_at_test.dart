import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/data/local/mappers/attachment_mapper.dart';
import 'package:kharcha/data/local/mappers/budget_mapper.dart';
import 'package:kharcha/data/local/mappers/category_mapper.dart';
import 'package:kharcha/data/local/mappers/expense_mapper.dart';
import 'package:kharcha/data/local/mappers/income_mapper.dart';
import 'package:kharcha/data/local/mappers/payment_method_mapper.dart';
import 'package:kharcha/data/local/mappers/recurring_rule_mapper.dart';
import 'package:kharcha/domain/models/attachment.dart' as domain;
import 'package:kharcha/domain/models/budget.dart' as domain;
import 'package:kharcha/domain/models/category.dart' as domain;
import 'package:kharcha/domain/models/enums.dart';
import 'package:kharcha/domain/models/expense.dart' as domain;
import 'package:kharcha/domain/models/income.dart' as domain;
import 'package:kharcha/domain/models/payment_method.dart' as domain;
import 'package:kharcha/domain/models/recurring_rule.dart' as domain;

/// Regression coverage for the Gate 10 bug (2026-09-05): every syncable
/// entity's `toCompanion(dirty: true)` used to leave `local_updated_at`
/// absent, so it stayed null forever except after a soft-delete. That
/// silently defeated the Gate 4 CAS conflict-resolution fix (it can never
/// prove a local edit is newer than the server's without this timestamp)
/// and crashed `_logConflictLoss` with a null-check error the first time a
/// dirty row's push actually hit a CAS mismatch — see docs/DECISIONS.md.
///
/// Each entity's mapper now stamps `local_updated_at` to "now" whenever
/// `dirty` is true, and leaves it untouched (`Value.absent()`) when clean —
/// a `dirty: false` call must never claim the row was *just* edited.
void main() {
  final now = DateTime.utc(2026, 1, 1);

  test('Expense.toCompanion stamps local_updated_at only when dirty', () {
    final expense = domain.Expense(
      id: 'e1',
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 100,
      spentAt: now,
      spentOn: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(expense.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(expense.toCompanion(dirty: false).localUpdatedAt.present, isFalse);
  });

  test('Income.toCompanion stamps local_updated_at only when dirty', () {
    final income = domain.Income(
      id: 'i1',
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 100,
      receivedAt: now,
      receivedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(income.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(income.toCompanion(dirty: false).localUpdatedAt.present, isFalse);
  });

  test('Category.toCompanion stamps local_updated_at only when dirty', () {
    final category = domain.Category(
      id: 'c1',
      householdId: 'h1',
      name: 'Groceries',
      kind: CategoryKind.expense,
      createdAt: now,
      updatedAt: now,
    );
    expect(category.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(category.toCompanion(dirty: false).localUpdatedAt.present, isFalse);
  });

  test('PaymentMethod.toCompanion stamps local_updated_at only when dirty', () {
    final method = domain.PaymentMethod(
      id: 'p1',
      householdId: 'h1',
      name: 'Cash',
      type: PayMethodType.cash,
      createdAt: now,
      updatedAt: now,
    );
    expect(method.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(method.toCompanion(dirty: false).localUpdatedAt.present, isFalse);
  });

  test('Budget.toCompanion stamps local_updated_at only when dirty', () {
    final budget = domain.Budget(
      id: 'b1',
      householdId: 'h1',
      scope: BudgetScope.household,
      amountPaise: 100,
      periodMonth: now,
      createdBy: 'u1',
      createdAt: now,
      updatedAt: now,
    );
    expect(budget.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(budget.toCompanion(dirty: false).localUpdatedAt.present, isFalse);
  });

  test('RecurringRule.toCompanion stamps local_updated_at only when dirty', () {
    final rule = domain.RecurringRule(
      id: 'r1',
      householdId: 'h1',
      userId: 'u1',
      title: 'Netflix',
      amountPaise: 100,
      frequency: RecurFrequency.monthly,
      startDate: now,
      nextDueDate: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(rule.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(rule.toCompanion(dirty: false).localUpdatedAt.present, isFalse);
  });

  test('Attachment.toCompanion stamps local_updated_at only when dirty', () {
    final attachment = domain.Attachment(
      id: 'a1',
      householdId: 'h1',
      expenseId: 'e1',
      storagePath: 'h1/e1/a1.jpg',
      uploadedBy: 'u1',
      createdAt: now,
      updatedAt: now,
    );
    expect(attachment.toCompanion(dirty: true).localUpdatedAt.present, isTrue);
    expect(
      attachment.toCompanion(dirty: false).localUpdatedAt.present,
      isFalse,
    );
  });
}
