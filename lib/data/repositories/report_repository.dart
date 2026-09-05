import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/expense.dart' as domain;
import '../../domain/models/report.dart';
import '../local/mappers/expense_mapper.dart';

part 'report_repository.g.dart';

/// Read-only Dashboard aggregates (spec §11.4, T-6.1). Every method takes
/// [monthStart] (an `AppTime.monthStart(...)` value) and queries the
/// half-open `[monthStart, monthStart + 1 month)` range — call again with a
/// different month for the month-over-month comparison. There is nothing to
/// write here, so — unlike the CRUD repositories — this never touches the
/// outbox or triggers a sync.
class ReportRepository {
  ReportRepository(this._db);

  final AppDatabase _db;

  Stream<int> watchExpenseTotal({
    required String householdId,
    required DateTime monthStart,
  }) => _db.reportDao.watchExpenseTotal(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
  );

  Stream<int> watchIncomeTotal({
    required String householdId,
    required DateTime monthStart,
  }) => _db.reportDao.watchIncomeTotal(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
  );

  Stream<List<GroupedTotal>> watchExpenseByMember({
    required String householdId,
    required DateTime monthStart,
  }) => _db.reportDao.watchExpenseByMember(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
  );

  Stream<List<GroupedTotal>> watchTopCategories({
    required String householdId,
    required DateTime monthStart,
    int limit = 5,
  }) => _db.reportDao.watchExpenseByCategory(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
    limit: limit,
  );

  Stream<List<GroupedTotal>> watchExpenseByPaymentMethod({
    required String householdId,
    required DateTime monthStart,
  }) => _db.reportDao.watchExpenseByPaymentMethod(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
  );

  Stream<List<domain.Expense>> watchRecentExpenses({
    required String householdId,
    int limit = 5,
  }) => _db.reportDao
      .watchRecentExpenses(householdId, limit: limit)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  /// Every category's expense total for the month, unranked and unlimited —
  /// the Analytics donut chart (spec §11.10, T-11.1) buckets these into top
  /// 8 + "Other" itself, unlike the Dashboard's fixed-`limit` top-categories
  /// card.
  Stream<List<GroupedTotal>> watchAllCategoryTotals({
    required String householdId,
    required DateTime monthStart,
  }) => _db.reportDao.watchExpenseByCategory(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
  );

  /// Household expense + income totals for [months] consecutive months
  /// ending at [endMonth] — the Analytics monthly trend chart (T-11.1).
  Stream<List<MonthlyTotal>> watchMonthlyTrend({
    required String householdId,
    required DateTime endMonth,
    int months = 12,
  }) => _db.reportDao.watchMonthlyTrend(
    householdId: householdId,
    endMonth: endMonth,
    months: months,
  );

  /// Per-member expense totals for [months] consecutive months ending at
  /// [endMonth] — the Analytics member-comparison grouped bar chart
  /// (T-11.1).
  Stream<List<MemberMonthTotal>> watchMemberMonthlyTrend({
    required String householdId,
    required DateTime endMonth,
    int months = 6,
  }) => _db.reportDao.watchMemberMonthlyTrend(
    householdId: householdId,
    endMonth: endMonth,
    months: months,
  );

  /// Per-category expense totals for [months] consecutive months ending at
  /// [endMonth] — the Analytics month-over-month table (T-11.1).
  Stream<List<CategoryMonthTotal>> watchCategoryMonthlyTrend({
    required String householdId,
    required DateTime endMonth,
    int months = 3,
  }) => _db.reportDao.watchCategoryMonthlyTrend(
    householdId: householdId,
    endMonth: endMonth,
    months: months,
  );

  /// Total expense spend per weekday for the month — the Analytics
  /// day-of-week chart (T-11.1).
  Stream<List<WeekdayTotal>> watchExpenseByWeekday({
    required String householdId,
    required DateTime monthStart,
  }) => _db.reportDao.watchExpenseByWeekday(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
  );

  /// Top [limit] merchants by expense spend for the month — the Analytics
  /// top-merchants list (T-11.1).
  Stream<List<GroupedTotal>> watchTopMerchants({
    required String householdId,
    required DateTime monthStart,
    int limit = 10,
  }) => _db.reportDao.watchTopMerchants(
    householdId: householdId,
    start: monthStart,
    end: AppTime.monthAfter(monthStart, 1),
    limit: limit,
  );
}

@Riverpod(keepAlive: true)
ReportRepository reportRepository(Ref ref) =>
    ReportRepository(ref.watch(appDatabaseProvider));
