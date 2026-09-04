import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/money/money.dart';
import '../../core/notifications/notification_service.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/budget.dart' as domain;
import '../../domain/models/budget_status.dart';
import '../../domain/models/enums.dart';
import 'budget_repository.dart';

part 'budget_alert_service.g.dart';

/// Evaluates every budget for the current month against its alert threshold
/// (spec §11.7), called after every expense save and on every app resume.
/// Fires at most once per budget per status transition per month: the last
/// *notified* status is persisted in `shared_preferences` keyed
/// `budget_alert_<budgetId>_<yyyyMM>`, cleared when the budget drops back to
/// `ok` so a later re-crossing into warning/exceeded counts as a new
/// transition and notifies again (spec's own wording — "once per status
/// transition per month", not "once per month").
class BudgetAlertService {
  BudgetAlertService(this._db, this._budgetRepo, this._notifications);

  final AppDatabase _db;
  final BudgetRepository _budgetRepo;
  final NotificationService _notifications;

  Future<void> evaluate(String householdId) async {
    final monthStart = AppTime.monthStart(DateTime.now().toUtc());
    final budgets = await _budgetRepo
        .watchForMonth(householdId, monthStart)
        .first;
    if (budgets.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    for (final budget in budgets) {
      final status = await _budgetRepo.watchStatus(budget).first;
      await _maybeNotify(prefs, budget, status);
    }
  }

  Future<void> _maybeNotify(
    SharedPreferences prefs,
    domain.Budget budget,
    BudgetStatus status,
  ) async {
    final key = _prefsKey(budget);
    if (status.health == BudgetHealth.ok) {
      await prefs.remove(key);
      return;
    }
    if (prefs.getString(key) == status.health.name) return;
    await prefs.setString(key, status.health.name);

    final label = await _labelFor(budget);
    final body = status.health == BudgetHealth.exceeded
        ? '$label budget exceeded by ${status.overspendPaise > 0 ? Money(status.overspendPaise).format() : Money.zero.format()}'
        : '$label budget ${(status.pct * 100).round()}% used — '
              '${Money(status.remainingPaise.clamp(0, status.effectiveBudgetPaise)).format()} '
              'left for ${AppTime.daysRemainingInMonth(budget.periodMonth)} days';

    await _notifications.show(
      id: budget.id.hashCode & 0x7fffffff,
      title: 'Budget alert',
      body: body,
    );
  }

  Future<String> _labelFor(domain.Budget budget) async {
    switch (budget.scope) {
      case BudgetScope.household:
        return 'Household';
      case BudgetScope.user:
        final profile = await _db.profileDao.findById(budget.userId!);
        return profile?.displayName ?? 'Member';
      case BudgetScope.category:
        final category = await _db.categoryDao.findById(budget.categoryId!);
        return category?.name ?? 'Category';
      case BudgetScope.userCategory:
        final profile = await _db.profileDao.findById(budget.userId!);
        final category = await _db.categoryDao.findById(budget.categoryId!);
        return '${profile?.displayName ?? 'Member'} · '
            '${category?.name ?? 'Category'}';
    }
  }

  String _prefsKey(domain.Budget budget) {
    final month = budget.periodMonth;
    final yyyyMM = '${month.year}${month.month.toString().padLeft(2, '0')}';
    return 'budget_alert_${budget.id}_$yyyyMM';
  }
}

@Riverpod(keepAlive: true)
BudgetAlertService budgetAlertService(Ref ref) => BudgetAlertService(
  ref.watch(appDatabaseProvider),
  ref.watch(budgetRepositoryProvider),
  NotificationService.instance,
);
