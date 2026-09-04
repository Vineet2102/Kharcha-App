import '../../core/money/money.dart';
import 'budget.dart' as domain;

enum BudgetHealth { ok, warning, exceeded }

/// Rollover amount carried into this month from the previous one (spec
/// §11.7, T-8.3): the previous month's unspent budget, floored at 0 (an
/// overspent previous month never turns into a *smaller* budget this
/// month). Zero whenever rollover is off or there is no previous-month
/// budget to roll over from.
int computeRolloverPaise({
  required bool isRollover,
  required int? previousBudgetAmountPaise,
  required int previousSpentPaise,
}) {
  if (!isRollover || previousBudgetAmountPaise == null) return 0;
  final unspent = previousBudgetAmountPaise - previousSpentPaise;
  return unspent > 0 ? unspent : 0;
}

/// A budget's computed-locally status for its month (spec §11.7: "Compute
/// this locally; do not store the derived number"). Not a synced entity —
/// like [GroupedTotal] in `report.dart`, this has no JSON codec.
class BudgetStatus {
  const BudgetStatus({
    required this.budget,
    required this.spentPaise,
    required this.rolloverPaise,
  });

  final domain.Budget budget;
  final int spentPaise;
  final int rolloverPaise;

  /// `amount + rollover`. Always > 0: `amount_paise` is DB-constrained to be
  /// positive and rollover is floored at 0.
  int get effectiveBudgetPaise => budget.amountPaise + rolloverPaise;

  double get pct => spentPaise / effectiveBudgetPaise;

  int get remainingPaise => effectiveBudgetPaise - spentPaise;

  int get overspendPaise => -remainingPaise;

  Money get spent => Money(spentPaise);
  Money get remaining => Money(remainingPaise);
  Money get effectiveBudget => Money(effectiveBudgetPaise);

  BudgetHealth get health {
    final threshold = budget.alertThresholdPct / 100;
    if (pct >= 1) return BudgetHealth.exceeded;
    if (pct >= threshold) return BudgetHealth.warning;
    return BudgetHealth.ok;
  }
}
