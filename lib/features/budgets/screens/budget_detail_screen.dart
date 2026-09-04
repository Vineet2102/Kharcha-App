import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../core/time/app_time.dart';
import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/budget_repository.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/budget.dart' as domain;
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/profile.dart' as domain;
import '../../shell/widgets/placeholder_screen.dart';

/// Add/edit a budget (spec §11.7, T-8.2). `id` is null for the "new" route;
/// [initialMonth] seeds the month field for a new budget (e.g. the month
/// currently shown on the Budgets list) and is ignored when editing.
///
/// RLS (`bud_write`) only lets the admin create a Household- or
/// Category-scoped budget; a member may only create/edit one that targets
/// themselves (User or Member+Category, with `user_id` forced to their own
/// id). This screen mirrors that client-side (T-8.1) by hiding the
/// disallowed scopes rather than letting a member submit one RLS will
/// reject anyway.
class BudgetDetailScreen extends ConsumerStatefulWidget {
  const BudgetDetailScreen({super.key, this.id, this.initialMonth});

  final String? id;
  final DateTime? initialMonth;

  @override
  ConsumerState<BudgetDetailScreen> createState() => _BudgetDetailScreenState();
}

class _BudgetDetailScreenState extends ConsumerState<BudgetDetailScreen> {
  final _amountController = TextEditingController();

  domain.Budget? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _amountError;

  BudgetScope _scope = BudgetScope.household;
  String? _userId;
  String? _categoryId;
  late DateTime _periodMonth =
      widget.initialMonth ?? AppTime.monthStart(DateTime.now().toUtc());
  bool _isRollover = false;
  int _alertThresholdPct = 80;
  bool _copyToNext12 = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  String? get _currentUserId =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  bool get _isAdmin => ref.read(currentProfileProvider).value?.isAdmin ?? false;

  Future<void> _load() async {
    if (widget.id != null) {
      final budget = await ref
          .read(budgetRepositoryProvider)
          .findById(widget.id!);
      if (budget != null) {
        _existing = budget;
        _amountController.text = budget.amount.rupees.toStringAsFixed(2);
        _scope = budget.scope;
        _userId = budget.userId;
        _categoryId = budget.categoryId;
        _periodMonth = budget.periodMonth;
        _isRollover = budget.isRollover;
        _alertThresholdPct = budget.alertThresholdPct;
      }
    } else if (!_isAdmin) {
      // A member's only allowed scopes target themselves.
      _scope = BudgetScope.user;
      _userId = _currentUserId;
    }
    if (mounted) setState(() => _loading = false);
  }

  List<BudgetScope> get _allowedScopes => _isAdmin
      ? BudgetScope.values
      : [BudgetScope.user, BudgetScope.userCategory];

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.id == null ? 'Add budget' : 'Budget'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.id != null && _existing == null) {
      return const PlaceholderScreen(title: 'Budget not found');
    }
    // A budget this member is neither the admin nor the target of — the
    // list screen never links here for one, but guard directly anyway.
    if (_existing != null && !_isAdmin && _existing!.userId != _currentUserId) {
      return const PlaceholderScreen(title: 'Budget');
    }

    final categories =
        (ref.watch(categoriesProvider).value ?? const <domain.Category>[])
            .where((c) => c.kind == CategoryKind.expense && !c.isArchived)
            .toList();
    final profiles =
        ref.watch(householdProfilesProvider).value ?? const <domain.Profile>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Add budget' : 'Edit budget'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AmountField(controller: _amountController, errorText: _amountError),
          const SizedBox(height: 24),
          Text('Scope', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scope in _allowedScopes)
                ChoiceChip(
                  label: Text(_scopeLabel(scope)),
                  selected: _scope == scope,
                  onSelected: widget.id == null
                      ? (_) => setState(() {
                          _scope = scope;
                          if (scope == BudgetScope.household) {
                            _userId = null;
                            _categoryId = null;
                          } else if (scope == BudgetScope.user) {
                            _categoryId = null;
                            _userId ??= _isAdmin ? null : _currentUserId;
                          } else if (scope == BudgetScope.category) {
                            _userId = null;
                          } else {
                            _userId ??= _isAdmin ? null : _currentUserId;
                          }
                        })
                      : null,
                ),
            ],
          ),
          if (_needsMember) ...[
            const SizedBox(height: 24),
            Text('Member', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final profile in profiles)
                  ChoiceChip(
                    label: Text(profile.displayName),
                    selected: profile.id == _userId,
                    onSelected: (_isAdmin && widget.id == null)
                        ? (_) => setState(() => _userId = profile.id)
                        : null,
                  ),
              ],
            ),
          ],
          if (_needsCategory) ...[
            const SizedBox(height: 24),
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final category in categories)
                  ChoiceChip(
                    avatar: Icon(iconForKey(category.iconKey), size: 18),
                    label: Text(category.name),
                    selected: category.id == _categoryId,
                    onSelected: widget.id == null
                        ? (_) => setState(() => _categoryId = category.id)
                        : null,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Month', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => setState(
                  () => _periodMonth = AppTime.monthAfter(_periodMonth, -1),
                ),
              ),
              Text(AppTime.monthLabel(_periodMonth)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => setState(
                  () => _periodMonth = AppTime.monthAfter(_periodMonth, 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Roll over unspent budget'),
            subtitle: const Text(
              "Last month's leftover (if any) is added to this month.",
            ),
            value: _isRollover,
            onChanged: (value) => setState(() => _isRollover = value),
          ),
          const SizedBox(height: 8),
          Text(
            'Alert threshold',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: _alertThresholdPct.toDouble(),
                  min: 1,
                  max: 100,
                  divisions: 99,
                  label: '$_alertThresholdPct%',
                  onChanged: (value) =>
                      setState(() => _alertThresholdPct = value.round()),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text('$_alertThresholdPct%', textAlign: TextAlign.end),
              ),
            ],
          ),
          if (widget.id == null) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Also create for the next 12 months'),
              value: _copyToNext12,
              onChanged: (value) =>
                  setState(() => _copyToNext12 = value ?? false),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
          if (widget.id != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _saving ? null : _confirmDelete,
              child: const Text('Delete'),
            ),
          ],
        ],
      ),
    );
  }

  bool get _needsMember =>
      _scope == BudgetScope.user || _scope == BudgetScope.userCategory;

  bool get _needsCategory =>
      _scope == BudgetScope.category || _scope == BudgetScope.userCategory;

  String _scopeLabel(BudgetScope scope) => switch (scope) {
    BudgetScope.household => 'Household',
    BudgetScope.user => 'Member',
    BudgetScope.category => 'Category',
    BudgetScope.userCategory => 'Member + category',
  };

  Future<void> _save() async {
    final money = Money.tryParse(_amountController.text);
    if (money == null) {
      setState(() => _amountError = 'Enter a valid amount.');
      return;
    }
    if (money.paise > AppConstants.maxTransactionAmountPaise) {
      setState(() => _amountError = 'Amount is too large.');
      return;
    }
    if (_needsMember && _userId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a member.')));
      return;
    }
    if (_needsCategory && _categoryId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pick a category.')));
      return;
    }

    setState(() {
      _saving = true;
      _amountError = null;
    });

    final repo = ref.read(budgetRepositoryProvider);
    final userId = _needsMember ? _userId : null;
    final categoryId = _needsCategory ? _categoryId : null;

    if (_existing == null) {
      final createdBy =
          ref.read(currentProfileProvider).value?.id ?? _currentUserId;
      if (createdBy == null) return;
      final result = await repo.create(
        householdId: AppConstants.seedHouseholdId,
        scope: _scope,
        userId: userId,
        categoryId: categoryId,
        amountPaise: money.paise,
        periodMonth: _periodMonth,
        isRollover: _isRollover,
        alertThresholdPct: _alertThresholdPct,
        createdBy: createdBy,
      );
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
        return;
      }
      if (_copyToNext12) {
        final created = await repo.findById(result.valueOrNull!);
        if (created != null) await repo.copyToNext12Months(created);
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } else {
      final result = await repo.update(
        _existing!.copyWith(
          scope: _scope,
          userId: userId,
          categoryId: categoryId,
          amountPaise: money.paise,
          periodMonth: _periodMonth,
          isRollover: _isRollover,
          alertThresholdPct: _alertThresholdPct,
        ),
      );
      if (!mounted) return;
      final failure = result.failureOrNull;
      if (failure != null) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(failure.message)));
        return;
      }
      Navigator.of(context).pop();
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete budget?'),
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
    if (confirmed != true || !mounted) return;
    await ref.read(budgetRepositoryProvider).delete(widget.id!);
    if (mounted) Navigator.of(context).pop();
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, this.errorText});

  final TextEditingController controller;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: Theme.of(context).textTheme.headlineMedium,
      decoration: InputDecoration(
        prefixText: '₹ ',
        labelText: 'Amount',
        errorText: errorText,
      ),
    );
  }
}
