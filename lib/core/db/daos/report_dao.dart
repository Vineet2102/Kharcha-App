import 'package:drift/drift.dart';

import '../../../domain/models/report.dart';
import '../../time/app_time.dart';
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

  /// Household expense total scoped to an optional member and/or category —
  /// the 4 budget scopes (spec §11.7, T-8.1) are exactly the 4 combinations
  /// of these two filters being present or absent.
  Stream<int> watchExpenseForScope({
    required String householdId,
    required DateTime start,
    required DateTime end,
    String? userId,
    String? categoryId,
  }) {
    var cond = _expensePeriod(householdId, start, end);
    if (userId != null) cond = cond & expenses.userId.equals(userId);
    if (categoryId != null) {
      cond = cond & expenses.categoryId.equals(categoryId);
    }
    final query = selectOnly(expenses)
      ..addColumns([expenses.amountPaise.sum()])
      ..where(cond);
    return query
        .map((row) => row.read(expenses.amountPaise.sum()) ?? 0)
        .watchSingle();
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

  /// Household expense + income totals for each of [months] consecutive
  /// months ending at [endMonth] inclusive — the Analytics monthly trend
  /// chart (spec §11.10, T-11.1). A single grouped-by-month query per table
  /// (rather than one query per month) so the whole chart stays one
  /// reactive stream; months with no rows at all come back as zero.
  Stream<List<MonthlyTotal>> watchMonthlyTrend({
    required String householdId,
    required DateTime endMonth,
    int months = 12,
  }) {
    final start = AppTime.monthAfter(endMonth, -(months - 1));
    final end = AppTime.monthAfter(endMonth, 1);
    final query = customSelect(
      '''
      SELECT strftime('%Y-%m', spent_on, 'unixepoch') AS ym,
             'expense' AS kind,
             SUM(amount_paise) AS total
      FROM expenses
      WHERE household_id = ?1 AND deleted_at IS NULL
        AND spent_on >= ?2 AND spent_on < ?3
      GROUP BY ym
      UNION ALL
      SELECT strftime('%Y-%m', received_on, 'unixepoch') AS ym,
             'income' AS kind,
             SUM(amount_paise) AS total
      FROM incomes
      WHERE household_id = ?1 AND deleted_at IS NULL
        AND received_on >= ?2 AND received_on < ?3
      GROUP BY ym
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {expenses, incomes},
    );
    return query.watch().map((rows) {
      final expenseByMonth = <String, int>{};
      final incomeByMonth = <String, int>{};
      for (final row in rows) {
        final ym = row.read<String>('ym');
        final total = row.read<int>('total');
        if (row.read<String>('kind') == 'expense') {
          expenseByMonth[ym] = total;
        } else {
          incomeByMonth[ym] = total;
        }
      }
      return [
        for (var i = 0; i < months; i++)
          _monthlyTotalFor(
            AppTime.monthAfter(start, i),
            expenseByMonth,
            incomeByMonth,
          ),
      ];
    });
  }

  MonthlyTotal _monthlyTotalFor(
    DateTime month,
    Map<String, int> expenseByMonth,
    Map<String, int> incomeByMonth,
  ) {
    final key = _ymKey(month);
    return MonthlyTotal(
      month: month,
      expensePaise: expenseByMonth[key] ?? 0,
      incomePaise: incomeByMonth[key] ?? 0,
    );
  }

  /// Per-member expense totals for each of [months] consecutive months
  /// ending at [endMonth] inclusive — the Analytics member-comparison
  /// grouped bar chart (spec §11.10, T-11.1). Sparse: only (month, member)
  /// pairs with at least one expense are returned.
  Stream<List<MemberMonthTotal>> watchMemberMonthlyTrend({
    required String householdId,
    required DateTime endMonth,
    int months = 6,
  }) {
    final start = AppTime.monthAfter(endMonth, -(months - 1));
    final end = AppTime.monthAfter(endMonth, 1);
    final query = customSelect(
      '''
      SELECT strftime('%Y-%m', spent_on, 'unixepoch') AS ym,
             user_id AS user_id,
             SUM(amount_paise) AS total
      FROM expenses
      WHERE household_id = ?1 AND deleted_at IS NULL
        AND spent_on >= ?2 AND spent_on < ?3
      GROUP BY ym, user_id
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {expenses},
    );
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          MemberMonthTotal(
            month: _parseYm(row.read<String>('ym')),
            userId: row.read<String>('user_id'),
            amountPaise: row.read<int>('total'),
          ),
      ],
    );
  }

  /// Per-category expense totals for each of [months] consecutive months
  /// ending at [endMonth] inclusive — the Analytics month-over-month table
  /// (spec §11.10, T-11.1). Uncategorised expenses are excluded, same as
  /// [watchExpenseByCategory].
  Stream<List<CategoryMonthTotal>> watchCategoryMonthlyTrend({
    required String householdId,
    required DateTime endMonth,
    int months = 3,
  }) {
    final start = AppTime.monthAfter(endMonth, -(months - 1));
    final end = AppTime.monthAfter(endMonth, 1);
    final query = customSelect(
      '''
      SELECT strftime('%Y-%m', spent_on, 'unixepoch') AS ym,
             category_id AS category_id,
             SUM(amount_paise) AS total
      FROM expenses
      WHERE household_id = ?1 AND deleted_at IS NULL AND category_id IS NOT NULL
        AND spent_on >= ?2 AND spent_on < ?3
      GROUP BY ym, category_id
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {expenses},
    );
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          CategoryMonthTotal(
            month: _parseYm(row.read<String>('ym')),
            categoryId: row.read<String>('category_id'),
            amountPaise: row.read<int>('total'),
          ),
      ],
    );
  }

  /// Total expense spend for each weekday within `[start, end)` — the
  /// Analytics day-of-week chart (spec §11.10, T-11.1). [WeekdayTotal.weekday]
  /// uses Dart's convention (1 = Monday ... 7 = Sunday); SQLite's
  /// `strftime('%w', ...)` returns 0 = Sunday ... 6 = Saturday, converted
  /// here. Averaging by how many times each weekday occurred in the period
  /// is left to the caller, which owns the period bounds.
  Stream<List<WeekdayTotal>> watchExpenseByWeekday({
    required String householdId,
    required DateTime start,
    required DateTime end,
  }) {
    final query = customSelect(
      '''
      SELECT CAST(strftime('%w', spent_on, 'unixepoch') AS INTEGER) AS wd,
             SUM(amount_paise) AS total
      FROM expenses
      WHERE household_id = ?1 AND deleted_at IS NULL
        AND spent_on >= ?2 AND spent_on < ?3
      GROUP BY wd
      ''',
      variables: [
        Variable.withString(householdId),
        Variable.withDateTime(start),
        Variable.withDateTime(end),
      ],
      readsFrom: {expenses},
    );
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          WeekdayTotal(
            weekday: _sqliteWeekdayToDart(row.read<int>('wd')),
            totalPaise: row.read<int>('total'),
          ),
      ],
    );
  }

  /// Top [limit] merchants by total expense spend — the Analytics top
  /// merchants list (spec §11.10, T-11.1). `merchant` is a non-nullable
  /// column defaulting to `''`, so blank merchants are excluded rather than
  /// null-checked.
  Stream<List<GroupedTotal>> watchTopMerchants({
    required String householdId,
    required DateTime start,
    required DateTime end,
    int limit = 10,
  }) {
    final sumExpr = expenses.amountPaise.sum();
    final query = selectOnly(expenses)
      ..addColumns([expenses.merchant, sumExpr])
      ..where(
        _expensePeriod(householdId, start, end) &
            expenses.merchant.equals('').not(),
      )
      ..groupBy([expenses.merchant])
      ..orderBy([OrderingTerm.desc(sumExpr)])
      ..limit(limit);
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          GroupedTotal(
            key: row.read(expenses.merchant)!,
            amountPaise: row.read(sumExpr) ?? 0,
          ),
      ],
    );
  }

  static String _ymKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  static DateTime _parseYm(String ym) {
    final parts = ym.split('-');
    return DateTime.utc(int.parse(parts[0]), int.parse(parts[1]));
  }

  /// SQLite's `strftime('%w', ...)` is 0 = Sunday ... 6 = Saturday; Dart's
  /// `DateTime.weekday` is 1 = Monday ... 7 = Sunday.
  static int _sqliteWeekdayToDart(int sqliteWeekday) =>
      sqliteWeekday == 0 ? 7 : sqliteWeekday;

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
