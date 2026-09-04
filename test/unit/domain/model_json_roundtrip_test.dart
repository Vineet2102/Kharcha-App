import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/domain/models/attachment.dart';
import 'package:kharcha/domain/models/budget.dart';
import 'package:kharcha/domain/models/category.dart';
import 'package:kharcha/domain/models/enums.dart';
import 'package:kharcha/domain/models/expense.dart';
import 'package:kharcha/domain/models/household.dart';
import 'package:kharcha/domain/models/income.dart';
import 'package:kharcha/domain/models/payment_method.dart';
import 'package:kharcha/domain/models/profile.dart';
import 'package:kharcha/domain/models/recurring_rule.dart';

void main() {
  final now = DateTime.utc(2026, 9, 1, 12, 0, 0);

  test('Household round-trips through JSON', () {
    final model = Household(
      id: 'h1',
      name: 'Panicker Family',
      createdAt: now,
      updatedAt: now,
    );
    expect(Household.fromJson(model.toJson()), model);
  });

  test('Profile round-trips through JSON, including the role enum', () {
    final model = Profile(
      id: 'u1',
      householdId: 'h1',
      displayName: 'Vineet',
      role: MemberRole.admin,
      createdAt: now,
      updatedAt: now,
    );
    final roundTripped = Profile.fromJson(model.toJson());
    expect(roundTripped, model);
    expect(roundTripped.role, MemberRole.admin);
    expect(roundTripped.isAdmin, isTrue);
  });

  test('Category round-trips through JSON', () {
    final model = Category(
      id: 'c1',
      householdId: 'h1',
      name: 'Groceries',
      kind: CategoryKind.expense,
      createdAt: now,
      updatedAt: now,
    );
    expect(Category.fromJson(model.toJson()), model);
  });

  test('PaymentMethod round-trips through JSON', () {
    final model = PaymentMethod(
      id: 'p1',
      householdId: 'h1',
      name: 'UPI',
      type: PayMethodType.upi,
      createdAt: now,
      updatedAt: now,
    );
    expect(PaymentMethod.fromJson(model.toJson()), model);
  });

  test('Expense round-trips through JSON and exposes Money', () {
    final model = Expense(
      id: 'e1',
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 15000,
      spentAt: now,
      spentOn: now,
      createdAt: now,
      updatedAt: now,
    );
    final roundTripped = Expense.fromJson(model.toJson());
    expect(roundTripped, model);
    expect(roundTripped.amount.paise, 15000);
  });

  test('Income round-trips through JSON', () {
    final model = Income(
      id: 'i1',
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 500000,
      receivedAt: now,
      receivedOn: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(Income.fromJson(model.toJson()), model);
  });

  test('Attachment round-trips through JSON', () {
    final model = Attachment(
      id: 'a1',
      householdId: 'h1',
      expenseId: 'e1',
      storagePath: 'h1/e1/a1.jpg',
      uploadedBy: 'u1',
      createdAt: now,
      updatedAt: now,
    );
    expect(Attachment.fromJson(model.toJson()), model);
  });

  test(
    'Budget round-trips through JSON, including the user_category enum value',
    () {
      final model = Budget(
        id: 'b1',
        householdId: 'h1',
        scope: BudgetScope.userCategory,
        userId: 'u1',
        categoryId: 'c1',
        amountPaise: 500000,
        periodMonth: DateTime.utc(2026, 9, 1),
        createdBy: 'u1',
        createdAt: now,
        updatedAt: now,
      );
      final json = model.toJson();
      expect(json['scope'], 'user_category');
      expect(Budget.fromJson(json), model);
    },
  );

  test('RecurringRule round-trips through JSON', () {
    final model = RecurringRule(
      id: 'r1',
      householdId: 'h1',
      userId: 'u1',
      title: 'Rent',
      amountPaise: 2500000,
      frequency: RecurFrequency.monthly,
      startDate: now,
      nextDueDate: now,
      createdAt: now,
      updatedAt: now,
    );
    expect(RecurringRule.fromJson(model.toJson()), model);
  });
}
