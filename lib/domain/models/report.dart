/// One grouping key (a member/category/payment-method id, or a merchant
/// string) paired with its summed `amount_paise` for a period — the
/// Dashboard's per-member and top-categories breakdowns (spec §11.4,
/// T-6.1) and, in Phase 11, Analytics' category donut, payment-method
/// split, and top-merchants list. Not a synced entity, so (unlike the
/// other domain models) this has no JSON codec.
class GroupedTotal {
  const GroupedTotal({required this.key, required this.amountPaise});

  final String key;
  final int amountPaise;
}

/// One month's household expense + income totals — the Analytics monthly
/// trend chart (spec §11.10, T-11.1). [month] is always a month-start value.
class MonthlyTotal {
  const MonthlyTotal({
    required this.month,
    required this.expensePaise,
    required this.incomePaise,
  });

  final DateTime month;
  final int expensePaise;
  final int incomePaise;
}

/// One (month, member) expense total — the Analytics member-comparison
/// grouped bar chart (spec §11.10, T-11.1). Only combinations with at least
/// one expense appear; a caller wanting a dense month×member grid fills the
/// gaps with zero itself.
class MemberMonthTotal {
  const MemberMonthTotal({
    required this.month,
    required this.userId,
    required this.amountPaise,
  });

  final DateTime month;
  final String userId;
  final int amountPaise;
}

/// One (month, category) expense total — the Analytics month-over-month
/// table (spec §11.10, T-11.1). Same sparse-grid contract as
/// [MemberMonthTotal].
class CategoryMonthTotal {
  const CategoryMonthTotal({
    required this.month,
    required this.categoryId,
    required this.amountPaise,
  });

  final DateTime month;
  final String categoryId;
  final int amountPaise;
}

/// A weekday's total expense spend for a period — the Analytics
/// day-of-week chart (spec §11.10, T-11.1). [weekday] uses Dart's
/// `DateTime.weekday` convention (1 = Monday ... 7 = Sunday). The average
/// (total ÷ how many times that weekday occurred in the period) is computed
/// by the caller, which already knows the period bounds.
class WeekdayTotal {
  const WeekdayTotal({required this.weekday, required this.totalPaise});

  final int weekday;
  final int totalPaise;
}
