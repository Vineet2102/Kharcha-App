import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/domain/models/budget.dart';
import 'package:kharcha/domain/models/budget_status.dart';
import 'package:kharcha/domain/models/enums.dart';

void main() {
  group('isValidBudgetScopeShape', () {
    test('household requires no member and no category', () {
      expect(
        isValidBudgetScopeShape(BudgetScope.household, null, null),
        isTrue,
      );
      expect(
        isValidBudgetScopeShape(BudgetScope.household, 'u1', null),
        isFalse,
      );
      expect(
        isValidBudgetScopeShape(BudgetScope.household, null, 'c1'),
        isFalse,
      );
    });

    test('user requires a member and no category', () {
      expect(isValidBudgetScopeShape(BudgetScope.user, 'u1', null), isTrue);
      expect(isValidBudgetScopeShape(BudgetScope.user, null, null), isFalse);
      expect(isValidBudgetScopeShape(BudgetScope.user, 'u1', 'c1'), isFalse);
    });

    test('category requires a category and no member', () {
      expect(isValidBudgetScopeShape(BudgetScope.category, null, 'c1'), isTrue);
      expect(
        isValidBudgetScopeShape(BudgetScope.category, null, null),
        isFalse,
      );
      expect(
        isValidBudgetScopeShape(BudgetScope.category, 'u1', 'c1'),
        isFalse,
      );
    });

    test('userCategory requires both a member and a category', () {
      expect(
        isValidBudgetScopeShape(BudgetScope.userCategory, 'u1', 'c1'),
        isTrue,
      );
      expect(
        isValidBudgetScopeShape(BudgetScope.userCategory, 'u1', null),
        isFalse,
      );
      expect(
        isValidBudgetScopeShape(BudgetScope.userCategory, null, 'c1'),
        isFalse,
      );
    });
  });

  group('computeRolloverPaise', () {
    test('zero when rollover is off', () {
      expect(
        computeRolloverPaise(
          isRollover: false,
          previousBudgetAmountPaise: 100000,
          previousSpentPaise: 0,
        ),
        0,
      );
    });

    test('zero when there is no previous-month budget to roll over from', () {
      expect(
        computeRolloverPaise(
          isRollover: true,
          previousBudgetAmountPaise: null,
          previousSpentPaise: 0,
        ),
        0,
      );
    });

    test('carries the unspent amount when the previous month was under', () {
      expect(
        computeRolloverPaise(
          isRollover: true,
          previousBudgetAmountPaise: 500000,
          previousSpentPaise: 300000,
        ),
        200000,
      );
    });

    test('floors at 0 when the previous month was over budget', () {
      expect(
        computeRolloverPaise(
          isRollover: true,
          previousBudgetAmountPaise: 500000,
          previousSpentPaise: 700000,
        ),
        0,
      );
    });
  });

  group('BudgetStatus.health', () {
    Budget budgetWith({int amountPaise = 100000, int alertThresholdPct = 80}) {
      final now = DateTime.utc(2026, 9, 1);
      return Budget(
        id: 'b1',
        householdId: 'h1',
        scope: BudgetScope.household,
        amountPaise: amountPaise,
        periodMonth: now,
        alertThresholdPct: alertThresholdPct,
        createdBy: 'u1',
        createdAt: now,
        updatedAt: now,
      );
    }

    test('ok below the threshold', () {
      final status = BudgetStatus(
        budget: budgetWith(),
        spentPaise: 79999,
        rolloverPaise: 0,
      );
      expect(status.health, BudgetHealth.ok);
    });

    test('warning at exactly the threshold', () {
      final status = BudgetStatus(
        budget: budgetWith(),
        spentPaise: 80000,
        rolloverPaise: 0,
      );
      expect(status.health, BudgetHealth.warning);
    });

    test('warning just under 100%', () {
      final status = BudgetStatus(
        budget: budgetWith(),
        spentPaise: 99999,
        rolloverPaise: 0,
      );
      expect(status.health, BudgetHealth.warning);
    });

    test('exceeded at exactly 100%', () {
      final status = BudgetStatus(
        budget: budgetWith(),
        spentPaise: 100000,
        rolloverPaise: 0,
      );
      expect(status.health, BudgetHealth.exceeded);
      expect(status.remainingPaise, 0);
      expect(status.overspendPaise, 0);
    });

    test('exceeded past 100% reports the overspend amount', () {
      final status = BudgetStatus(
        budget: budgetWith(),
        spentPaise: 123000,
        rolloverPaise: 0,
      );
      expect(status.health, BudgetHealth.exceeded);
      expect(status.overspendPaise, 23000);
    });

    test(
      'rollover raises the effective budget the threshold is measured against',
      () {
        // Without the 100000 rollover, 150000 spent against a 100000 budget
        // would already be exceeded (150%); with it, effective budget is
        // 200000 and 150000 is only 75% — below the 80% threshold, still ok.
        final status = BudgetStatus(
          budget: budgetWith(),
          spentPaise: 150000,
          rolloverPaise: 100000,
        );
        expect(status.effectiveBudgetPaise, 200000);
        expect(status.health, BudgetHealth.ok);

        final closerToLimit = BudgetStatus(
          budget: budgetWith(),
          spentPaise: 170000,
          rolloverPaise: 100000,
        );
        expect(closerToLimit.health, BudgetHealth.warning); // 85% of 200000
      },
    );

    test('a custom alert threshold changes where warning kicks in', () {
      final status50 = BudgetStatus(
        budget: budgetWith(alertThresholdPct: 50),
        spentPaise: 60000,
        rolloverPaise: 0,
      );
      expect(status50.health, BudgetHealth.warning);
    });
  });
}
