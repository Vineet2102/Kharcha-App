import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/income_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/income.dart' as domain;
import '../../../domain/models/profile.dart' as domain;
import '../../shell/widgets/placeholder_screen.dart';

/// Add/Edit Income (spec §11.6, T-7.2). `id` is null for the "new" route.
/// Same ownership rule as expenses (RLS `inc_update`/`inc_delete`, T-5.9's
/// sibling): the signed-in member can only edit if they own the entry or are
/// an admin — everyone else gets a read-only view.
class IncomeDetailScreen extends ConsumerStatefulWidget {
  const IncomeDetailScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<IncomeDetailScreen> createState() =>
      _IncomeDetailScreenState();
}

class _IncomeDetailScreenState extends ConsumerState<IncomeDetailScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _sourceController = TextEditingController();

  domain.Income? _existing;
  bool _loading = true;
  bool _saving = false;

  String? _categoryId;
  String? _receivedByUserId;
  DateTime _receivedAt = DateTime.now().toUtc();
  String? _amountError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _sourceController.dispose();
    super.dispose();
  }

  String? get _currentUserId =>
      ref.read(supabaseClientProvider).auth.currentUser?.id;

  bool get _isAdmin => ref.read(currentProfileProvider).value?.isAdmin ?? false;

  bool get _canEdit {
    if (_existing == null) return true;
    return _isAdmin || _existing!.userId == _currentUserId;
  }

  Future<void> _load() async {
    final userId = _currentUserId;

    if (widget.id != null) {
      final income = await ref
          .read(incomeRepositoryProvider)
          .findById(widget.id!);
      if (income != null) {
        _existing = income;
        _amountController.text = income.amount.rupees.toStringAsFixed(2);
        _noteController.text = income.note;
        _sourceController.text = income.source;
        _categoryId = income.categoryId;
        _receivedByUserId = income.userId;
        _receivedAt = income.receivedAt;
      }
    } else {
      _receivedByUserId = userId;
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.id == null ? 'Add income' : 'Income')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.id != null && _existing == null) {
      return const PlaceholderScreen(title: 'Income not found');
    }

    final categoriesAsync = ref.watch(categoriesProvider);
    final profilesAsync = ref.watch(householdProfilesProvider);

    if (!_canEdit) {
      return _ReadOnlyIncomeView(
        income: _existing!,
        categories: categoriesAsync.value ?? const [],
        receiver: profilesAsync.value?.firstWhere(
          (p) => p.id == _existing!.userId,
          orElse: () => domain.Profile(
            id: _existing!.userId,
            householdId: _existing!.householdId,
            displayName: 'Unknown',
            createdAt: _existing!.createdAt,
            updatedAt: _existing!.updatedAt,
          ),
        ),
      );
    }

    final categories = (categoriesAsync.value ?? const <domain.Category>[])
        .where((c) => c.kind == CategoryKind.income && !c.isArchived)
        .toList();
    final profiles = profilesAsync.value ?? const <domain.Profile>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Add income' : 'Edit income'),
        actions: [
          if (widget.id != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _AmountField(controller: _amountController, errorText: _amountError),
          const SizedBox(height: 24),
          Text('Category', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _CategoryChips(
            categories: categories,
            selectedId: _categoryId,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 24),
          Text('Date', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _DatePicker(
            receivedAt: _receivedAt,
            onChanged: (value) => setState(() => _receivedAt = value),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _sourceController,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Source'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _noteController,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note'),
          ),
          if (_isAdmin && profiles.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Received by', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final profile in profiles)
                  ChoiceChip(
                    label: Text(profile.displayName),
                    selected: profile.id == _receivedByUserId,
                    onSelected: (_) =>
                        setState(() => _receivedByUserId = profile.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 32),
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
        ],
      ),
    );
  }

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
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    if (_receivedAt.isAfter(tomorrow)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Date cannot be more than 1 day in the future.'),
        ),
      );
      return;
    }

    final userId = _receivedByUserId ?? _currentUserId;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _amountError = null;
    });

    final repo = ref.read(incomeRepositoryProvider);
    if (_existing == null) {
      await repo.create(
        householdId: AppConstants.seedHouseholdId,
        userId: userId,
        amountPaise: money.paise,
        categoryId: _categoryId,
        receivedAt: _receivedAt,
        note: _noteController.text.trim(),
        source: _sourceController.text.trim(),
      );
    } else {
      await repo.update(
        _existing!.copyWith(
          userId: userId,
          amountPaise: money.paise,
          categoryId: _categoryId,
          receivedAt: _receivedAt,
          note: _noteController.text.trim(),
          source: _sourceController.text.trim(),
        ),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
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
    );
    if (confirmed != true || !mounted) return;
    await ref.read(incomeRepositoryProvider).delete(widget.id!);
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

class _CategoryChips extends StatelessWidget {
  const _CategoryChips({
    required this.categories,
    required this.selectedId,
    required this.onSelected,
  });

  final List<domain.Category> categories;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in categories)
          ChoiceChip(
            avatar: Icon(iconForKey(category.iconKey), size: 18),
            label: Text(category.name),
            selected: category.id == selectedId,
            onSelected: (_) => onSelected(category.id),
          ),
      ],
    );
  }
}

class _DatePicker extends StatelessWidget {
  const _DatePicker({required this.receivedAt, required this.onChanged});

  final DateTime receivedAt;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final local = receivedAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ChoiceChip(
          label: const Text('Today'),
          selected: isToday,
          onSelected: (_) => onChanged(
            DateTime(now.year, now.month, now.day, local.hour, local.minute)
                .toUtc(),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text('${local.day}/${local.month}/${local.year}'),
          onPressed: () => _pick(context),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final local = receivedAt.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null) return;
    onChanged(
      DateTime(date.year, date.month, date.day, local.hour, local.minute)
          .toUtc(),
    );
  }
}

/// Non-owner, non-admin view of someone else's income (T-7.2's sibling to
/// T-5.9): every field is shown, nothing is editable.
class _ReadOnlyIncomeView extends StatelessWidget {
  const _ReadOnlyIncomeView({
    required this.income,
    required this.categories,
    required this.receiver,
  });

  final domain.Income income;
  final List<domain.Category> categories;
  final domain.Profile? receiver;

  @override
  Widget build(BuildContext context) {
    domain.Category? category;
    for (final c in categories) {
      if (c.id == income.categoryId) category = c;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Income')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            income.amount.format(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (category != null)
            ListTile(
              leading: Icon(iconForKey(category.iconKey)),
              title: Text(category.name),
              contentPadding: EdgeInsets.zero,
            ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(receiver?.displayName ?? 'Unknown'),
            contentPadding: EdgeInsets.zero,
          ),
          if (income.source.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(income.source),
              contentPadding: EdgeInsets.zero,
            ),
          if (income.note.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(income.note),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}
