import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../core/time/app_time.dart';
import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/income_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/income.dart' as domain;
import '../../../domain/models/profile.dart' as domain;
import '../../../routing/routes.dart';

/// Income List (spec §11.6, T-7.2): reverse-chronological, grouped by date,
/// same shape as the Expense List but without filters/search/infinite
/// scroll — income entries are far less frequent than expenses, so a single
/// unbounded stream is simplest and sufficient.
class IncomeListScreen extends ConsumerWidget {
  const IncomeListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomesAsync = ref.watch(householdIncomesProvider);
    final currentUserId = ref
        .watch(supabaseClientProvider)
        .auth
        .currentUser
        ?.id;
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final profilesById = {for (final p in profiles) p.id: p};

    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push(AppRoutes.incomeNew),
        child: const Icon(Icons.add),
      ),
      body: incomesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(child: Text('Error: $error')),
        data: (incomes) {
          if (incomes.isEmpty) {
            return const Center(child: Text('No income logged yet.'));
          }
          final total = Money(incomes.fold(0, (sum, i) => sum + i.amountPaise));
          final groups = _groupByDate(incomes);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total', style: Theme.of(context).textTheme.labelLarge),
                    Text(
                      total.format(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _DateGroupSection(
                      date: group.date,
                      incomes: group.items,
                      categoriesById: categoriesById,
                      profilesById: profilesById,
                      currentUserId: currentUserId,
                      isAdmin: isAdmin,
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DateGroup {
  _DateGroup(this.date, this.items);
  final DateTime date;
  final List<domain.Income> items;
}

List<_DateGroup> _groupByDate(List<domain.Income> incomes) {
  final groups = <_DateGroup>[];
  for (final income in incomes) {
    if (groups.isNotEmpty && groups.last.date.isAtSameMomentAs(income.receivedOn)) {
      groups.last.items.add(income);
    } else {
      groups.add(_DateGroup(income.receivedOn, [income]));
    }
  }
  return groups;
}

class _DateGroupSection extends StatelessWidget {
  const _DateGroupSection({
    required this.date,
    required this.incomes,
    required this.categoriesById,
    required this.profilesById,
    required this.currentUserId,
    required this.isAdmin,
  });

  final DateTime date;
  final List<domain.Income> incomes;
  final Map<String, domain.Category> categoriesById;
  final Map<String, domain.Profile> profilesById;
  final String? currentUserId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final dayTotal = Money(incomes.fold(0, (sum, i) => sum + i.amountPaise));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_dateLabel(date), style: Theme.of(context).textTheme.labelLarge),
              Text(dayTotal.format(), style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
        ),
        for (final income in incomes)
          _IncomeRow(
            income: income,
            category: categoriesById[income.categoryId],
            receiver: profilesById[income.userId],
            canEdit: isAdmin || income.userId == currentUserId,
          ),
      ],
    );
  }

  static String _dateLabel(DateTime date) {
    final today = AppTime.calendarDate(DateTime.now().toUtc());
    final yesterday = today.subtract(const Duration(days: 1));
    if (date.isAtSameMomentAs(today)) return 'Today';
    if (date.isAtSameMomentAs(yesterday)) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }
}

class _IncomeRow extends ConsumerWidget {
  const _IncomeRow({
    required this.income,
    required this.category,
    required this.receiver,
    required this.canEdit,
  });

  final domain.Income income;
  final domain.Category? category;
  final domain.Profile? receiver;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = income.source.isNotEmpty
        ? income.source
        : (category?.name ?? 'Uncategorised');

    return Dismissible(
      key: ValueKey(income.id),
      direction: canEdit
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        color: Theme.of(context).colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (_) => showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete income?'),
          content: const Text('This cannot be undone.'),
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
      onDismissed: (_) => ref.read(incomeRepositoryProvider).delete(income.id),
      child: ListTile(
        onTap: () => context.push(AppRoutes.incomeDetailPath(income.id)),
        leading: CircleAvatar(
          backgroundColor: category == null ? null : colourFromHex(category!.colourHex),
          foregroundColor: Colors.white,
          child: Icon(category == null ? Icons.category : iconForKey(category!.iconKey)),
        ),
        title: Text(title),
        subtitle: receiver == null ? null : Text(receiver!.displayName),
        trailing: Text(
          income.amount.format(),
          style: const TextStyle(color: Colors.green),
        ),
      ),
    );
  }
}
