import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/money/money.dart';
import '../../../core/time/app_time.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/budget.dart' as domain;
import '../../../domain/models/budget_status.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/profile.dart' as domain;
import '../../../routing/routes.dart';

/// Budgets screen (spec §11.7, T-8.2): the month's budgets grouped by
/// scope, each with a live progress bar, plus a summary of how many are
/// ok/warning/exceeded.
class BudgetListScreen extends ConsumerStatefulWidget {
  const BudgetListScreen({super.key});

  @override
  ConsumerState<BudgetListScreen> createState() => _BudgetListScreenState();
}

class _BudgetListScreenState extends ConsumerState<BudgetListScreen> {
  DateTime _month = AppTime.monthStart(DateTime.now().toUtc());

  // Populated live by each row as its own status stream emits — see
  // [_BudgetRow]. Only used to render the top summary counts; each row's
  // own bar is independently live regardless of this map.
  final Map<String, BudgetHealth> _healthByBudgetId = {};

  void _reportHealth(String budgetId, BudgetHealth health) {
    if (_healthByBudgetId[budgetId] == health) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _healthByBudgetId[budgetId] = health);
    });
  }

  @override
  Widget build(BuildContext context) {
    final budgetsAsync = ref.watch(budgetsForMonthProvider(_month));
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final profilesById = {for (final p in profiles) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () =>
                  setState(() => _month = AppTime.monthAfter(_month, -1)),
            ),
            Text(AppTime.monthLabel(_month)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: AppTime.isFutureMonth(AppTime.monthAfter(_month, 1))
                  ? null
                  : () =>
                        setState(() => _month = AppTime.monthAfter(_month, 1)),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.budgetNew, extra: _month),
        child: const Icon(Icons.add),
      ),
      body: budgetsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Could not load budgets: $error')),
        data: (budgets) {
          if (budgets.isEmpty) {
            return const Center(child: Text('No budgets for this month yet.'));
          }
          final groups = <BudgetScope, List<domain.Budget>>{
            for (final scope in BudgetScope.values)
              scope: budgets.where((b) => b.scope == scope).toList(),
          }..removeWhere((_, list) => list.isEmpty);
          // Only count health for budgets still in this month's list — a
          // deleted (or navigated-away) budget's last-known health must not
          // keep inflating the summary above.
          final currentHealths = [
            for (final b in budgets)
              if (_healthByBudgetId[b.id] != null) _healthByBudgetId[b.id]!,
          ];

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _SummaryHeader(
                total: budgets.length,
                counted: currentHealths.length,
                ok: currentHealths.where((h) => h == BudgetHealth.ok).length,
                warning: currentHealths
                    .where((h) => h == BudgetHealth.warning)
                    .length,
                exceeded: currentHealths
                    .where((h) => h == BudgetHealth.exceeded)
                    .length,
              ),
              const SizedBox(height: 16),
              for (final entry in groups.entries) ...[
                Text(
                  _scopeGroupLabel(entry.key),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                for (final budget in entry.value)
                  _BudgetRow(
                    budget: budget,
                    category: categoriesById[budget.categoryId],
                    member: profilesById[budget.userId],
                    onHealth: (health) => _reportHealth(budget.id, health),
                  ),
                const SizedBox(height: 12),
              ],
            ],
          );
        },
      ),
    );
  }

  String _scopeGroupLabel(BudgetScope scope) => switch (scope) {
    BudgetScope.household => 'HOUSEHOLD',
    BudgetScope.user => 'BY MEMBER',
    BudgetScope.category => 'BY CATEGORY',
    BudgetScope.userCategory => 'MEMBER + CATEGORY',
  };
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.total,
    required this.counted,
    required this.ok,
    required this.warning,
    required this.exceeded,
  });

  final int total;
  final int counted;
  final int ok;
  final int warning;
  final int exceeded;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _SummaryChip(label: 'OK', count: ok, color: Colors.green.shade700),
            _SummaryChip(
              label: 'Warning',
              count: warning,
              color: Colors.orange.shade800,
            ),
            _SummaryChip(
              label: 'Exceeded',
              count: exceeded,
              color: Theme.of(context).colorScheme.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          '$count',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: color),
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

class _BudgetRow extends ConsumerWidget {
  const _BudgetRow({
    required this.budget,
    required this.category,
    required this.member,
    required this.onHealth,
  });

  final domain.Budget budget;
  final domain.Category? category;
  final domain.Profile? member;
  final ValueChanged<BudgetHealth> onHealth;

  String get _label => switch (budget.scope) {
    BudgetScope.household => 'Household',
    BudgetScope.user => member?.displayName ?? 'Member',
    BudgetScope.category => category?.name ?? 'Category',
    BudgetScope.userCategory =>
      '${member?.displayName ?? 'Member'} · ${category?.name ?? 'Category'}',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return InkWell(
      onTap: () => context.push(AppRoutes.budgetDetailPath(budget.id)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: StreamBuilder<BudgetStatus>(
          stream: ref.watch(budgetRepositoryProvider).watchStatus(budget),
          builder: (context, snapshot) {
            final status = snapshot.data;
            if (status == null) {
              return Text(_label);
            }
            WidgetsBinding.instance.addPostFrameCallback(
              (_) => onHealth(status.health),
            );
            final colour = switch (status.health) {
              BudgetHealth.ok => Colors.green.shade700,
              BudgetHealth.warning => Colors.orange.shade800,
              BudgetHealth.exceeded => Theme.of(context).colorScheme.error,
            };
            return Column(
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
                      : '${status.remaining.format()} left',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colour),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
