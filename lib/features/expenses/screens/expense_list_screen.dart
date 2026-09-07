import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../core/time/app_time.dart';
import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/expense_repository.dart';
import '../../../data/repositories/payment_method_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/expense.dart' as domain;
import '../../../domain/models/expense_filter.dart';
import '../../../domain/models/payment_method.dart' as domain;
import '../../../domain/models/profile.dart' as domain;
import '../../../routing/routes.dart';
import '../controllers/expense_list_preset_filter_controller.dart';
import '../widgets/expense_filter_sheet.dart';

/// Expense List (spec §11.3, T-5.7/T-5.8): reverse-chronological, grouped by
/// date, infinite scroll, combinable filters, free-text search, swipe
/// actions.
class ExpenseListScreen extends ConsumerStatefulWidget {
  const ExpenseListScreen({super.key});

  @override
  ConsumerState<ExpenseListScreen> createState() => _ExpenseListScreenState();
}

class _ExpenseListScreenState extends ConsumerState<ExpenseListScreen> {
  static const _pageSize = 50;

  late ExpenseFilter _filter = _defaultFilter();
  int _limit = _pageSize;
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  Timer? _debounce;

  static ExpenseFilter _defaultFilter() {
    final start = AppTime.monthStart(DateTime.now().toUtc());
    final end = AppTime.monthAfter(start, 1).subtract(const Duration(days: 1));
    return ExpenseFilter(startDate: start, endDate: end);
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    // Dashboard "tap a member" handoff (spec §11.4 card 3): apply it once,
    // then clear it so it doesn't reapply on a later, unrelated tab visit.
    final preset = ref.read(expenseListPresetFilterControllerProvider);
    if (preset != null) {
      _filter = preset;
      ref.read(expenseListPresetFilterControllerProvider.notifier).clear();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 400) {
      setState(() => _limit += _pageSize);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      setState(() {
        _filter = _filter.copyWith(searchText: value);
        _limit = _pageSize;
      });
    });
  }

  Future<void> _openFilterSheet({
    required List<domain.Category> categories,
    required List<domain.PaymentMethod> methods,
    required List<domain.Profile> profiles,
    required String? currentUserId,
  }) async {
    final result = await showExpenseFilterSheet(
      context,
      initial: _filter,
      categories: categories,
      methods: methods,
      profiles: profiles,
      currentUserId: currentUserId,
    );
    if (result != null) {
      setState(() {
        _filter = result;
        _limit = _pageSize;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _filter = _defaultFilter();
      _limit = _pageSize;
      _searchController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(expenseRepositoryProvider);
    final householdId = ref.watch(currentHouseholdIdProvider) ?? '';
    final currentUserId = ref
        .watch(supabaseClientProvider)
        .auth
        .currentUser
        ?.id;
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final methods = ref.watch(paymentMethodsProvider).value ?? const [];
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};
    final methodsById = {for (final m in methods) m.id: m};
    final profilesById = {for (final p in profiles) p.id: p};

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            icon: Icon(
              _filter.hasActiveFilters
                  ? Icons.filter_alt
                  : Icons.filter_alt_outlined,
            ),
            onPressed: () => _openFilterSheet(
              categories: categories,
              methods: methods,
              profiles: profiles,
              currentUserId: currentUserId,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search notes, merchants',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          StreamBuilder<int>(
            stream: repo.watchFilteredTotal(
              householdId: householdId,
              filter: _filter,
            ),
            builder: (context, snapshot) {
              final total = Money(snapshot.data ?? 0);
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    Text(
                      total.format(),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              );
            },
          ),
          if (_filter.hasActiveFilters)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _clearFilters,
                  child: const Text('Clear filters'),
                ),
              ),
            ),
          Expanded(
            child: StreamBuilder<List<domain.Expense>>(
              stream: repo.watchFiltered(
                householdId: householdId,
                filter: _filter,
                limit: _limit,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final expenses = snapshot.data!;
                if (expenses.isEmpty) {
                  return _EmptyState(
                    hasFilters: _filter.hasActiveFilters,
                    onClear: _clearFilters,
                  );
                }
                final groups = _groupByDate(expenses);
                return ListView.builder(
                  controller: _scrollController,
                  itemCount: groups.length,
                  itemBuilder: (context, index) {
                    final group = groups[index];
                    return _DateGroupSection(
                      date: group.date,
                      expenses: group.items,
                      categoriesById: categoriesById,
                      methodsById: methodsById,
                      profilesById: profilesById,
                      currentUserId: currentUserId,
                      isAdmin: isAdmin,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DateGroup {
  _DateGroup(this.date, this.items);
  final DateTime date;
  final List<domain.Expense> items;
}

List<_DateGroup> _groupByDate(List<domain.Expense> expenses) {
  final groups = <_DateGroup>[];
  for (final expense in expenses) {
    if (groups.isNotEmpty &&
        groups.last.date.isAtSameMomentAs(expense.spentOn)) {
      groups.last.items.add(expense);
    } else {
      groups.add(_DateGroup(expense.spentOn, [expense]));
    }
  }
  return groups;
}

class _DateGroupSection extends StatelessWidget {
  const _DateGroupSection({
    required this.date,
    required this.expenses,
    required this.categoriesById,
    required this.methodsById,
    required this.profilesById,
    required this.currentUserId,
    required this.isAdmin,
  });

  final DateTime date;
  final List<domain.Expense> expenses;
  final Map<String, domain.Category> categoriesById;
  final Map<String, domain.PaymentMethod> methodsById;
  final Map<String, domain.Profile> profilesById;
  final String? currentUserId;
  final bool isAdmin;

  @override
  Widget build(BuildContext context) {
    final dayTotal = Money(expenses.fold(0, (sum, e) => sum + e.amountPaise));
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
              Text(
                _dateLabel(date),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                dayTotal.format(),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        for (final expense in expenses)
          _ExpenseRow(
            expense: expense,
            category: categoriesById[expense.categoryId],
            method: methodsById[expense.paymentMethodId],
            payer: profilesById[expense.userId],
            canEdit: isAdmin || expense.userId == currentUserId,
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

class _ExpenseRow extends ConsumerWidget {
  const _ExpenseRow({
    required this.expense,
    required this.category,
    required this.method,
    required this.payer,
    required this.canEdit,
  });

  final domain.Expense expense;
  final domain.Category? category;
  final domain.PaymentMethod? method;
  final domain.Profile? payer;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final title = expense.note.isNotEmpty
        ? expense.note
        : (category?.name ?? 'Uncategorised');

    return Dismissible(
      key: ValueKey(expense.id),
      direction: DismissDirection.horizontal,
      background: Container(
        color: Theme.of(context).colorScheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.copy_outlined),
      ),
      secondaryBackground: Container(
        color: canEdit
            ? Theme.of(context).colorScheme.errorContainer
            : Colors.grey,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          context.push(AppRoutes.expenseNew, extra: expense);
          return false;
        }
        if (!canEdit) return false;
        return showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete expense?'),
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
        );
      },
      onDismissed: (_) =>
          ref.read(expenseRepositoryProvider).delete(expense.id),
      child: ListTile(
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
        subtitle: Row(
          children: [
            if (payer != null) ...[
              Text(payer!.displayName),
              const SizedBox(width: 8),
            ],
            if (method != null)
              Icon(iconForPaymentMethodType(method!.type), size: 14),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (expense.isDirty)
              const Padding(
                padding: EdgeInsets.only(right: 6),
                child: Icon(Icons.cloud_off, size: 16),
              ),
            Text(expense.amount.format()),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilters, required this.onClear});

  final bool hasFilters;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // T-M2.10: a genuinely empty household (no filters applied at
          // all) reads oddly with filter-specific copy — distinguish it
          // from "your filters excluded everything".
          Text(
            hasFilters
                ? 'No expenses match these filters.'
                : 'No expenses yet — tap + to add your first one.',
          ),
          if (hasFilters) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onClear, child: const Text('Clear filters')),
          ],
        ],
      ),
    );
  }
}
