import 'package:drift/drift.dart';

import '../../../domain/models/report.dart';
import '../app_database.dart';
import '../tables/expenses_table.dart';
import '../tables/incomes_table.dart';

part 'report_dao.g.dart';

/// Aggregate queries backing the Dashboard (spec §11.4, T-6.1): household
/// total, per-member, per-category, per-payment-method, and (by calling the
/// total queries again with a different `[start, end)`) month-over-month.
/// Every period is a half-open `[start, end)` range of `spent_on`/
/// `received_on` calendar dates — callers pass `AppTime.monthStart(...)` and
/// `AppTime.monthAfter(start, 1)` as the bounds.
@DriftAccessor(tables: [Expenses, Incomes])
class ReportDao extends DatabaseAccessor<AppDatabase> with _$ReportDaoMixin {
  ReportDao(super.db);

  Stream<int> watchExpenseTotal({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) {
    final query = selectOnly(expenses)
      ..addColumns([expenses.amountPaise.sum()])
      ..where(_expensePeriod(householdId, start, end));
    return query
        .map((row) => row.read(expenses.amountPaise.sum()) ?? 0)
        .watchSingle();
  }

  Stream<int> watchIncomeTotal({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) {
    final query = selectOnly(incomes)
      ..addColumns([incomes.amountPaise.sum()])
      ..where(
        incomes.householdId.equals(householdId) &
            incomes.deletedAt.isNull() &
            incomes.receivedOn.isBiggerOrEqualValue(start) &
            incomes.receivedOn.isSmallerThanValue(end),
      );
    return query
        .map((row) => row.read(incomes.amountPaise.sum()) ?? 0)
        .watchSingle();
  }

  /// Per-member expense totals, largest first — the Dashboard's per-member
  /// breakdown (spec §11.4 card 3). `user_id` is never null, so every row
  /// counted in [watchExpenseTotal] appears in exactly one group here.
  Stream<List<GroupedTotal>> watchExpenseByMember({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) => _groupedExpenseTotal(
    householdId: householdId,
    start: start,
    end: end,
    keyColumn: expenses.userId,
  );

  /// Per-category expense totals, largest first — the Dashboard's top
  /// categories card (spec §11.4 card 4) and, later, Analytics. Uncategorised
  /// expenses (`category_id IS NULL`) are excluded.
  Stream<List<GroupedTotal>> watchExpenseByCategory({
    required String householdId,
    required DateTime start,
    required DateTime end,
    int? limit,
  }) => _groupedExpenseTotal(
    householdId: householdId,
    start: start,
    end: end,
    keyColumn: expenses.categoryId,
    excludeNullKey: true,
    limit: limit,
  );

  /// Per-payment-method expense totals, largest first. Not yet surfaced on
  /// the Dashboard (only cards 1/3/4/5 ship in Phase 6) — reserved for
  /// Analytics (Phase 11).
  Stream<List<GroupedTotal>> watchExpenseByPaymentMethod({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) => _groupedExpenseTotal(
    householdId: householdId,
    start: start,
    end: end,
    keyColumn: expenses.paymentMethodId,
    excludeNullKey: true,
  );

  Stream<List<GroupedTotal>> _groupedExpenseTotal({
    required String householdId,
    required DateTime start,
    required DateTime end,
    required GeneratedColumn<String> keyColumn,
    bool excludeNullKey = false,
    int? limit,
  }) {
    final sumExpr = expenses.amountPaise.sum();
    var cond = _expensePeriod(householdId, start, end);
    if (excludeNullKey) cond = cond & keyColumn.isNotNull();
    final query = selectOnly(expenses)
      ..addColumns([keyColumn, sumExpr])
      ..where(cond)
      ..groupBy([keyColumn])
      ..orderBy([OrderingTerm.desc(sumExpr)]);
    if (limit != null) query.limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          GroupedTotal(
            key: row.read(keyColumn)!,
            amountPaise: row.read(sumExpr) ?? 0,
          ),
      ],
    );
  }

  Expression<bool> _expensePeriod(
    String householdId,
    DateTime start,
    DateTime end,
  ) =>
      expenses.householdId.equals(householdId) &
      expenses.deletedAt.isNull() &
      expenses.spentOn.isBiggerOrEqualValue(start) &
      expenses.spentOn.isSmallerThanValue(end);

  /// Last [limit] expenses across the whole household, most recent first —
  /// the Dashboard's recent-activity card (spec §11.4 card 5). Deliberately
  /// ignores the selected month: "recent" always means most-recent-overall.
  Stream<List<Expense>> watchRecentExpenses(
    String householdId, {
    int limit = 5,
  }) {
    return (select(expenses)
          ..where(
            (t) => t.householdId.equals(householdId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.spentAt)])
          ..limit(limit))
        .watch();
  }
}
