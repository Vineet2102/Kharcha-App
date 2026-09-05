import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/recurring_rule.dart' as domain;
import '../../../routing/routes.dart';

/// Recurring rules list (spec §11.8, T-9.2): every household rule, most
/// recently due first, active ones ahead of inactive/ended ones. Editing or
/// deleting a rule you don't own and aren't an admin for is blocked here
/// the same way the list hides those controls for expenses/income — RLS
/// (`rec_write`) would reject it anyway.
class RecurringListScreen extends ConsumerWidget {
  const RecurringListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rulesAsync = ref.watch(householdRecurringRulesProvider);
    final currentUserId = ref
        .watch(supabaseClientProvider)
        .auth
        .currentUser
        ?.id;
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.recurringNew),
        child: const Icon(Icons.add),
      ),
      body: rulesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Could not load: $error')),
        data: (rules) {
          if (rules.isEmpty) {
            return const Center(child: Text('No recurring rules yet.'));
          }
          final sorted = [...rules]
            ..sort((a, b) {
              if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
              return a.nextDueDate.compareTo(b.nextDueDate);
            });
          return ListView.builder(
            itemCount: sorted.length,
            itemBuilder: (context, index) {
              final rule = sorted[index];
              return _RecurringRuleRow(
                rule: rule,
                canEdit: isAdmin || rule.userId == currentUserId,
              );
            },
          );
        },
      ),
    );
  }
}

class _RecurringRuleRow extends ConsumerWidget {
  const _RecurringRuleRow({required this.rule, required this.canEdit});

  final domain.RecurringRule rule;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpense = rule.kind == TxnKind.expense;
    final subtitle = [
      _frequencyLabel(rule),
      if (!rule.isActive)
        'Inactive'
      else
        'Next: ${_dateLabel(rule.nextDueDate)}',
      rule.autoPost ? 'Auto-post' : 'Confirm each time',
    ].join(' · ');

    return Dismissible(
      key: ValueKey(rule.id),
      direction: canEdit ? DismissDirection.endToStart : DismissDirection.none,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete recurring rule?'),
          content: const Text(
            'This stops future occurrences. Transactions already posted '
            'are not affected.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      ),
      onDismissed: (_) => ref.read(recurringRepositoryProvider).delete(rule.id),
      child: Opacity(
        opacity: rule.isActive ? 1 : 0.5,
        child: ListTile(
          onTap: () => context.push(AppRoutes.recurringDetailPath(rule.id)),
          leading: CircleAvatar(
            backgroundColor: isExpense
                ? Theme.of(context).colorScheme.errorContainer
                : Colors.green.shade100,
            child: Icon(
              isExpense ? Icons.arrow_upward : Icons.arrow_downward,
              color: isExpense
                  ? Theme.of(context).colorScheme.error
                  : Colors.green.shade800,
            ),
          ),
          title: Text(rule.title),
          subtitle: Text(subtitle),
          trailing: Text(
            rule.amount.format(),
            style: TextStyle(color: isExpense ? null : Colors.green.shade800),
          ),
        ),
      ),
    );
  }
}

String _frequencyLabel(domain.RecurringRule rule) {
  final n = rule.intervalN;
  final unit = switch (rule.frequency) {
    RecurFrequency.daily => n == 1 ? 'day' : 'days',
    RecurFrequency.weekly => n == 1 ? 'week' : 'weeks',
    RecurFrequency.monthly => n == 1 ? 'month' : 'months',
    RecurFrequency.yearly => n == 1 ? 'year' : 'years',
  };
  return n == 1 ? 'Every $unit' : 'Every $n $unit';
}

String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';
