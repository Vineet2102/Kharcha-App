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
}

@Riverpod(keepAlive: true)
ReportRepository reportRepository(Ref ref) =>
    ReportRepository(ref.watch(appDatabaseProvider));
