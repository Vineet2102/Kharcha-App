import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/domain/models/budget.dart';
import 'package:kharcha/domain/models/enums.dart';
import 'package:kharcha/domain/models/expense_filter.dart';
import 'package:kharcha/domain/models/income.dart';
import 'package:kharcha/domain/models/recurring_rule.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1);

  test('Income.amount wraps amountPaise as Money', () {
    final income = Income(
      id: 'i1',
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 50000,
      receivedAt: now,
      receivedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(income.amount.paise, 50000);
  });

  test('Budget.amount wraps amountPaise as Money', () {
    final budget = Budget(
      id: 'b1',
      householdId: 'h1',
      scope: BudgetScope.household,
      amountPaise: 100000,
      periodMonth: now,
      createdBy: 'u1',
      createdAt: now,
      updatedAt: now,
    );
    expect(budget.amount.paise, 100000);
  });

  test('RecurringRule.amount wraps amountPaise as Money', () {
    final rule = RecurringRule(
      id: 'r1',
      householdId: 'h1',
      userId: 'u1',
      title: 'Netflix',
      amountPaise: 49900,
      frequency: RecurFrequency.monthly,
      startDate: now,
      nextDueDate: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(rule.amount.paise, 49900);
  });

  group('ExpenseFilter.hasActiveFilters', () {
    test('false for the default (no filters applied)', () {
      expect(const ExpenseFilter().hasActiveFilters, isFalse);
    });

    test('true when any single field is set', () {
      expect(const ExpenseFilter(memberIds: ['u1']).hasActiveFilters, isTrue);
      expect(const ExpenseFilter(categoryIds: ['c1']).hasActiveFilters, isTrue);
      expect(
        const ExpenseFilter(paymentMethodIds: ['p1']).hasActiveFilters,
        isTrue,
      );
      expect(const ExpenseFilter(minAmountPaise: 100).hasActiveFilters, isTrue);
      expect(const ExpenseFilter(maxAmountPaise: 100).hasActiveFilters, isTrue);
      expect(
        const ExpenseFilter(onlyWithReceipts: true).hasActiveFilters,
        isTrue,
      );
      expect(
        const ExpenseFilter(searchText: 'zomato').hasActiveFilters,
        isTrue,
      );
    });

    test('whitespace-only search text does not count as active', () {
      expect(const ExpenseFilter(searchText: '   ').hasActiveFilters, isFalse);
    });
  });
}
