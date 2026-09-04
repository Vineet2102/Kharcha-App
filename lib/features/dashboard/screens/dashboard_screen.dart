import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../core/time/app_time.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/report_repository.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../domain/models/budget.dart' as domain;
import '../../../domain/models/budget_status.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/expense.dart' as domain;
import '../../../domain/models/expense_filter.dart';
import '../../../domain/models/profile.dart' as domain;
import '../../../domain/models/report.dart';
import '../../../routing/routes.dart';
import '../../expenses/controllers/expense_list_preset_filter_controller.dart';
import '../controllers/selected_month_controller.dart';

/// Household + per-member monthly totals (spec §11.4, T-6.1..T-6.5, T-8.4).
/// Ships cards 1, 2, 3, 4, 5 — pending recurring (card 6, Phase 9) lands
/// with its own phase. Card 7 (the sync/offline banner) is already rendered
/// above every tab by [AppShell].
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: _MonthSelector(month: month)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncEngineProvider).sync(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _HouseholdSummaryCard(monthStart: month),
            const SizedBox(height: 12),
            _BudgetProgressCard(monthStart: month),
            const SizedBox(height: 12),
            _MemberBreakdownCard(monthStart: month),
            const SizedBox(height: 12),
            _TopCategoriesCard(monthStart: month),
            const SizedBox(height: 12),
            const _RecentActivityCard(),
          ],
        ),
      ),
    );
  }
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard({
    required this.title,
    required this.child,
    this.onSeeAll,
  });

  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (onSeeAll != null)
                  TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyCardBody extends StatelessWidget {
  const _EmptyCardBody(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}

class _MonthSelector extends ConsumerWidget {
  const _MonthSelector({required this.month});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(selectedMonthControllerProvider.notifier);
    final isCurrentMonth = AppTime.isSameIstMonth(
      month,
      DateTime.now().toUtc(),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: controller.previousMonth,
          tooltip: 'Previous month',
        ),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final picked = await showDialog<DateTime>(
                context: context,
                builder: (context) => _MonthYearPickerDialog(initial: month),
              );
              if (picked != null) controller.setMonth(picked);
            },
            child: Text(AppTime.monthLabel(month)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrentMonth ? null : controller.nextMonth,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _MonthYearPickerDialog extends StatefulWidget {
  const _MonthYearPickerDialog({required this.initial});
  final DateTime initial;

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final canGoForward = _year < AppTime.nowIst().year;
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _year--),
          ),
          Text('$_year'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoForward ? () => setState(() => _year++) : null,
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          childAspectRatio: 2,
          children: [
            for (var m = 1; m <= 12; m++) _MonthCell(year: _year, month: m),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({required this.year, required this.month});
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final value = DateTime.utc(year, month);
    final disabled = AppTime.isFutureMonth(value);
    return TextButton(
      onPressed: disabled ? null : () => Navigator.of(context).pop(value),
      child: Text(AppTime.monthLabelShort(value).split(' ').first),
    );
  }
}

/// Card 1 (spec §11.4): total spent, total income, net saved, and a %
/// change in spend vs the previous month.
class _HouseholdSummaryCard extends ConsumerWidget {
  const _HouseholdSummaryCard({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final previousMonth = AppTime.monthAfter(monthStart, -1);

    return _DashboardCard(
      title: 'This month',
      child: StreamBuilder<int>(
        stream: repo.watchExpenseTotal(
          householdId: AppConstants.seedHouseholdId,
          monthStart: monthStart,
        ),
        builder: (context, expenseSnap) {
          final expenseTotal = expenseSnap.data ?? 0;
          return StreamBuilder<int>(
            stream: repo.watchIncomeTotal(
              householdId: AppConstants.seedHouseholdId,
              monthStart: monthStart,
            ),
            builder: (context, incomeSnap) {
              final incomeTotal = incomeSnap.data ?? 0;
              return StreamBuilder<int>(
                stream: repo.watchExpenseTotal(
                  householdId: AppConstants.seedHouseholdId,
                  monthStart: previousMonth,
                ),
                builder: (context, prevSnap) {
                  final previousTotal = prevSnap.data ?? 0;
                  return _SummaryBody(
                    expenseTotal: expenseTotal,
                    incomeTotal: incomeTotal,
                    previousExpenseTotal: previousTotal,
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _SummaryBody extends StatelessWidget {
  const _SummaryBody({
    required this.expenseTotal,
    required this.incomeTotal,
    required this.previousExpenseTotal,
  });

  final int expenseTotal;
  final int incomeTotal;
  final int previousExpenseTotal;

  @override
  Widget build(BuildContext context) {
    final net = Money(incomeTotal - expenseTotal);
    // No previous-month spend to compare against — omit the change row
    // rather than divide by zero (spec T-6.5).
    final double? changePct = previousExpenseTotal == 0
        ? null
        : ((expenseTotal - previousExpenseTotal) / previousExpenseTotal) * 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryRow(label: 'Spent', value: Money(expenseTotal).format()),
        _SummaryRow(
          label: 'Income',
          value: Money(incomeTotal).format(),
          onTap: () => context.push(AppRoutes.income),
        ),
        _SummaryRow(
          label: 'Net saved',
          value: net.format(),
          valueColor: net.isNegative
              ? Theme.of(context).colorScheme.error
              : Colors.green.shade700,
        ),
        if (changePct != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                changePct >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
                size: 16,
                color: changePct >= 0
                    ? Theme.of(context).colorScheme.error
                    : Colors.green.shade700,
              ),
              const SizedBox(width: 4),
              Text(
                '${changePct.abs().toStringAsFixed(0)}% vs last month',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(color: valueColor),
          ),
        ],
      ),
    );
    return onTap == null ? row : InkWell(onTap: onTap, child: row);
  }
}

/// Card 2 (spec §11.4/§11.7, T-8.4): each of this month's budgets, showing
/// spent, remaining, days left, and the daily allowance the remainder
/// works out to. Absent entirely when there are no budgets for the month
/// (nothing to show, and no "create one?" nag per §0 rule 4).
class _BudgetProgressCard extends ConsumerWidget {
  const _BudgetProgressCard({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgetsAsync = ref.watch(budgetsForMonthProvider(monthStart));
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final profilesById = {for (final p in profiles) p.id: p};

    final budgets = budgetsAsync.value ?? const <domain.Budget>[];
    if (budgets.isEmpty) return const SizedBox.shrink();

    return _DashboardCard(
      title: 'Budgets',
      onSeeAll: () => context.push(AppRoutes.budgets),
      child: Column(
        children: [
          for (final budget in budgets)
            _BudgetProgressRow(
              budget: budget,
              category: categoriesById[budget.categoryId],
              member: profilesById[budget.userId],
            ),
        ],
      ),
    );
  }
}

class _BudgetProgressRow extends ConsumerWidget {
  const _BudgetProgressRow({
    required this.budget,
    required this.category,
    required this.member,
  });

  final domain.Budget budget;
  final domain.Category? category;
  final domain.Profile? member;

  String get _label => switch (budget.scope) {
    BudgetScope.household => 'Household',
    BudgetScope.user => member?.displayName ?? 'Member',
    BudgetScope.category => category?.name ?? 'Category',
    BudgetScope.userCategory =>
      '${member?.displayName ?? 'Member'} · ${category?.name ?? 'Category'}',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return StreamBuilder<BudgetStatus>(
      stream: ref.watch(budgetRepositoryProvider).watchStatus(budget),
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null) return const SizedBox.shrink();
        final daysLeft = AppTime.daysRemainingInMonth(budget.periodMonth);
        final dailyAllowance = daysLeft > 0
            ? Money((status.remainingPaise / daysLeft).round())
            : Money.zero;
        final colour = switch (status.health) {
          BudgetHealth.ok => Colors.green.shade700,
          BudgetHealth.warning => Colors.orange.shade800,
          BudgetHealth.exceeded => Theme.of(context).colorScheme.error,
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_label),
                  Text(
                    '${status.spent.format()} / ${status.effectiveBudget.format()}',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: status.pct.clamp(0, 1).toDouble(),
                  minHeight: 6,
                  color: colour,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                status.health == BudgetHealth.exceeded
                    ? 'Exceeded by ${Money(status.overspendPaise).format()}'
                    : '${status.remaining.format()} left · ${dailyAllowance.format()}/day '
                          'for $daysLeft day${daysLeft == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: colour),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Card 3 (spec §11.4): horizontal bars, sorted descending, tap to filter
/// the Expense List to that member.
class _MemberBreakdownCard extends ConsumerWidget {
  const _MemberBreakdownCard({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final profilesById = {for (final p in profiles) p.id: p};

    return _DashboardCard(
      title: 'Per member',
      child: StreamBuilder<List<GroupedTotal>>(
        stream: repo.watchExpenseByMember(
          householdId: AppConstants.seedHouseholdId,
          monthStart: monthStart,
        ),
        builder: (context, snapshot) {
          final totals = snapshot.data ?? const [];
          if (totals.isEmpty) {
            return const _EmptyCardBody('No expenses logged this month yet.');
          }
          final householdTotal = totals.fold(
            0,
            (sum, g) => sum + g.amountPaise,
          );
          return Column(
            children: [
              for (final group in totals)
                _MemberBar(
                  profile: profilesById[group.key],
                  amountPaise: group.amountPaise,
                  fraction: householdTotal == 0
                      ? 0
                      : group.amountPaise / householdTotal,
                  onTap: () => _filterExpensesToMember(
                    context,
                    ref,
                    group.key,
                    monthStart,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

void _filterExpensesToMember(
  BuildContext context,
  WidgetRef ref,
  String userId,
  DateTime monthStart,
) {
  final monthEnd = AppTime.monthAfter(
    monthStart,
    1,
  ).subtract(const Duration(days: 1));
  ref
      .read(expenseListPresetFilterControllerProvider.notifier)
      .set(
        ExpenseFilter(
          startDate: monthStart,
          endDate: monthEnd,
          memberIds: [userId],
        ),
      );
  context.go(AppRoutes.expenses);
}

class _MemberBar extends StatelessWidget {
  const _MemberBar({
    required this.profile,
    required this.amountPaise,
    required this.fraction,
    required this.onTap,
  });

  final domain.Profile? profile;
  final int amountPaise;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(profile?.displayName ?? 'Unknown'),
                Row(
                  children: [
                    Text(Money(amountPaise).format()),
                    const SizedBox(width: 6),
                    Text(
                      '${(fraction * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.clamp(0, 1).toDouble(),
                minHeight: 6,
                color: profile == null
                    ? null
                    : colourFromHex(profile!.colourHex),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card 4 (spec §11.4): top 5 categories by spend, with a "See all" link to
/// Analytics.
class _TopCategoriesCard extends ConsumerWidget {
  const _TopCategoriesCard({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};

    return _DashboardCard(
      title: 'Top categories',
      onSeeAll: () => context.go(AppRoutes.analytics),
      child: StreamBuilder<int>(
        stream: repo.watchExpenseTotal(
          householdId: AppConstants.seedHouseholdId,
          monthStart: monthStart,
        ),
        builder: (context, totalSnap) {
          final householdTotal = totalSnap.data ?? 0;
          return StreamBuilder<List<GroupedTotal>>(
            stream: repo.watchTopCategories(
              householdId: AppConstants.seedHouseholdId,
              monthStart: monthStart,
            ),
            builder: (context, snapshot) {
              final totals = snapshot.data ?? const [];
              if (totals.isEmpty) {
                return const _EmptyCardBody(
                  'No categorised expenses this month yet.',
                );
              }
              return Column(
                children: [
                  for (final group in totals)
                    _CategoryRow(
                      category: categoriesById[group.key],
                      amountPaise: group.amountPaise,
                      percent: householdTotal == 0
                          ? 0
                          : group.amountPaise / householdTotal * 100,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.amountPaise,
    required this.percent,
  });

  final domain.Category? category;
  final int amountPaise;
  final double percent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: category == null
                ? null
                : colourFromHex(category!.colourHex),
            foregroundColor: Colors.white,
            child: Icon(
              category == null ? Icons.category : iconForKey(category!.iconKey),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(category?.name ?? 'Uncategorised')),
          Text('${percent.toStringAsFixed(0)}%'),
          const SizedBox(width: 8),
          Text(Money(amountPaise).format()),
        ],
      ),
    );
  }
}

/// Card 5 (spec §11.4): the household's last 5 expenses, most recent first.
class _RecentActivityCard extends ConsumerWidget {
  const _RecentActivityCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final profilesById = {for (final p in profiles) p.id: p};

    return _DashboardCard(
      title: 'Recent activity',
      child: StreamBuilder<List<domain.Expense>>(
        stream: repo.watchRecentExpenses(
          householdId: AppConstants.seedHouseholdId,
        ),
        builder: (context, snapshot) {
          final recent = snapshot.data ?? const [];
          if (recent.isEmpty) {
            return const _EmptyCardBody('No expenses logged yet.');
          }
          return Column(
            children: [
              for (final expense in recent)
                _RecentExpenseRow(
                  expense: expense,
                  category: categoriesById[expense.categoryId],
                  payer: profilesById[expense.userId],
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecentExpenseRow extends StatelessWidget {
  const _RecentExpenseRow({
    required this.expense,
    required this.category,
    required this.payer,
  });

  final domain.Expense expense;
  final domain.Category? category;
  final domain.Profile? payer;

  @override
  Widget build(BuildContext context) {
    final title = expense.note.isNotEmpty
        ? expense.note
        : (category?.name ?? 'Uncategorised');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: () => context.push(AppRoutes.expenseDetailPath(expense.id)),
      leading: CircleAvatar(
        backgroundColor: category == null
            ? null
            : colourFromHex(category!.colourHex),
        foregroundColor: Colors.white,
        child: Icon(
          category == null ? Icons.category : iconForKey(category!.iconKey),
        ),
      ),
      title: Text(title),
      subtitle: payer == null ? null : Text(payer!.displayName),
      trailing: Text(expense.amount.format()),
    );
  }
}
