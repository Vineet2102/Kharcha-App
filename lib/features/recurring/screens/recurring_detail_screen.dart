import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/payment_method_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/recurring_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/payment_method.dart' as domain;
import '../../../domain/models/profile.dart' as domain;
import '../../../domain/models/recurring_rule.dart' as domain;
import '../../shell/widgets/placeholder_screen.dart';

/// Add/edit a recurring rule (spec §11.8, T-9.2). `id` is null for the
/// "new" route. RLS (`rec_write`): own rule, or admin — mirrored
/// client-side the same way `BudgetDetailScreen` mirrors `bud_write`: a
/// member's rules are always for themselves, only an admin sees a member
/// picker. The `kind` (expense/income) is locked once a rule exists, same
/// precedent as a category's kind (T-5.2) — changing what a rule with
/// already-posted occurrences produces would be confusing.
class RecurringDetailScreen extends ConsumerStatefulWidget {
  const RecurringDetailScreen({super.key, this.id});

  final String? id;

  @override
  ConsumerState<RecurringDetailScreen> createState() =>
      _RecurringDetailScreenState();
}

class _RecurringDetailScreenState extends ConsumerState<RecurringDetailScreen> {
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  domain.RecurringRule? _existing;
  bool _loading = true;
  bool _saving = false;
  String? _amountError;

  TxnKind _kind = TxnKind.expense;
  String? _categoryId;
  String? _paymentMethodId;
  String? _userId;
  RecurFrequency _frequency = RecurFrequency.monthly;
  int _intervalN = 1;
  int? _dayOfMonth;
  DateTime _startDate = DateTime.now().toUtc();
  DateTime? _endDate;
  bool _autoPost = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _noteController.dispose();
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
    if (widget.id != null) {
      final rule = await ref
          .read(recurringRepositoryProvider)
          .findById(widget.id!);
      if (rule != null) {
        _existing = rule;
        _titleController.text = rule.title;
        _amountController.text = rule.amount.rupees.toStringAsFixed(2);
        _noteController.text = rule.note;
        _kind = rule.kind;
        _categoryId = rule.categoryId;
        _paymentMethodId = rule.paymentMethodId;
        _userId = rule.userId;
        _frequency = rule.frequency;
        _intervalN = rule.intervalN;
        _dayOfMonth = rule.dayOfMonth;
        _startDate = rule.startDate;
        _endDate = rule.endDate;
        _autoPost = rule.autoPost;
      }
    } else {
      _userId = _currentUserId;
      _startDate = DateTime.now().toUtc();
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.id == null ? 'Add recurring rule' : 'Recurring'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.id != null && _existing == null) {
      return const PlaceholderScreen(title: 'Recurring rule not found');
    }
    if (!_canEdit) {
      return _ReadOnlyRecurringView(rule: _existing!);
    }

    final categoriesAsync = ref.watch(categoriesProvider);
    final methodsAsync = ref.watch(paymentMethodsProvider);
    final profiles =
        ref.watch(householdProfilesProvider).value ?? const <domain.Profile>[];
    final wantedCategoryKind = _kind == TxnKind.expense
        ? CategoryKind.expense
        : CategoryKind.income;
    final categories = (categoriesAsync.value ?? const <domain.Category>[])
        .where((c) => c.kind == wantedCategoryKind && !c.isArchived)
        .toList();
    final methods = (methodsAsync.value ?? const <domain.PaymentMethod>[])
        .where((m) => !m.isArchived)
        .toList();

    final previewFrom = _existing?.nextDueDate ?? _startDate;
    final preview = ref
        .read(recurringRepositoryProvider)
        .previewOccurrences(
          from: previewFrom,
          frequency: _frequency,
          intervalN: _intervalN,
          dayOfMonth: _dayOfMonth,
          endDate: _endDate,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.id == null ? 'Add recurring rule' : 'Edit recurring',
        ),
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
          TextField(
            controller: _titleController,
            maxLength: 60,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 8),
          Text('Kind', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final kind in TxnKind.values)
                ChoiceChip(
                  label: Text(kind == TxnKind.expense ? 'Expense' : 'Income'),
                  selected: _kind == kind,
                  onSelected: widget.id == null
                      ? (_) => setState(() {
                          _kind = kind;
                          _categoryId = null;
                          if (kind == TxnKind.income) _paymentMethodId = null;
                        })
                      : null,
                ),
            ],
          ),
          const SizedBox(height: 16),
          _AmountField(controller: _amountController, errorText: _amountError),
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
                  onSelected: (_) => setState(() => _categoryId = category.id),
                ),
            ],
          ),
          if (_kind == TxnKind.expense) ...[
            const SizedBox(height: 24),
            Text(
              'Payment method',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in methods)
                  ChoiceChip(
                    avatar: Icon(
                      iconForPaymentMethodType(method.type),
                      size: 18,
                    ),
                    label: Text(method.name),
                    selected: method.id == _paymentMethodId,
                    onSelected: (_) =>
                        setState(() => _paymentMethodId = method.id),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          TextField(
            controller: _noteController,
            maxLength: 200,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
          const SizedBox(height: 24),
          Text('Repeats', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final freq in RecurFrequency.values)
                ChoiceChip(
                  label: Text(_frequencyChipLabel(freq)),
                  selected: _frequency == freq,
                  onSelected: (_) => setState(() {
                    _frequency = freq;
                    if (freq != RecurFrequency.monthly) _dayOfMonth = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Every'),
              const SizedBox(width: 8),
              SizedBox(
                width: 64,
                child: TextFormField(
                  initialValue: '$_intervalN',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                  onChanged: (value) {
                    final n = int.tryParse(value);
                    if (n != null && n >= 1 && n <= 60) {
                      setState(() => _intervalN = n);
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(_intervalUnitLabel(_frequency)),
            ],
          ),
          if (_frequency == RecurFrequency.monthly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('On day'),
                const SizedBox(width: 8),
                SizedBox(
                  width: 64,
                  child: TextFormField(
                    initialValue: '${_dayOfMonth ?? _startDate.day}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true),
                    onChanged: (value) {
                      final n = int.tryParse(value);
                      if (n != null && n >= 1 && n <= 31) {
                        setState(() => _dayOfMonth = n);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                const Text('of the month'),
              ],
            ),
          ],
          const SizedBox(height: 24),
          Text('Start date', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(_dateLabel(_startDate)),
            onPressed: widget.id == null ? () => _pickStartDate(context) : null,
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('End date', style: Theme.of(context).textTheme.labelLarge),
              if (_endDate != null)
                TextButton(
                  onPressed: () => setState(() => _endDate = null),
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined, size: 16),
            label: Text(
              _endDate == null ? 'No end date' : _dateLabel(_endDate!),
            ),
            onPressed: () => _pickEndDate(context),
          ),
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-post'),
            subtitle: Text(
              _autoPost
                  ? 'On: each occurrence posts automatically.'
                  : 'Off: each occurrence waits on the Dashboard for you to '
                        'confirm or skip it.',
            ),
            value: _autoPost,
            onChanged: (value) => setState(() => _autoPost = value),
          ),
          if (_isAdmin && profiles.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('For', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final profile in profiles)
                  ChoiceChip(
                    label: Text(profile.displayName),
                    selected: profile.id == _userId,
                    onSelected: (_) => setState(() => _userId = profile.id),
                  ),
              ],
            ),
          ],
          if (preview.isNotEmpty) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Next occurrences',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview.map(_dateLabel).join(', '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
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

  String _frequencyChipLabel(RecurFrequency freq) => switch (freq) {
    RecurFrequency.daily => 'Daily',
    RecurFrequency.weekly => 'Weekly',
    RecurFrequency.monthly => 'Monthly',
    RecurFrequency.yearly => 'Yearly',
  };

  String _intervalUnitLabel(RecurFrequency freq) {
    final plural = _intervalN != 1;
    return switch (freq) {
      RecurFrequency.daily => plural ? 'days' : 'day',
      RecurFrequency.weekly => plural ? 'weeks' : 'week',
      RecurFrequency.monthly => plural ? 'months' : 'month',
      RecurFrequency.yearly => plural ? 'years' : 'year',
    };
  }

  String _dateLabel(DateTime date) => '${date.day}/${date.month}/${date.year}';

  Future<void> _pickStartDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate.toLocal(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      _startDate = DateTime.utc(picked.year, picked.month, picked.day);
      _dayOfMonth ??= picked.day;
    });
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (_endDate ?? _startDate).toLocal(),
      firstDate: _startDate.toLocal(),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(
      () => _endDate = DateTime.utc(picked.year, picked.month, picked.day),
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
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a title.')));
      return;
    }
    final userId = _userId ?? _currentUserId;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _amountError = null;
    });

    // A monthly rule always carries an explicit day-of-month, defaulting to
    // the start date's — leaving it null would make `advanceDueDate` fall
    // back to *the previous occurrence's own (possibly already clamped)*
    // day each step, so a rule created on the 31st would drift down to the
    // 28th forever after its first February instead of returning to the
    // 31st in months that have one.
    final dayOfMonth = _frequency == RecurFrequency.monthly
        ? (_dayOfMonth ?? _startDate.day)
        : null;

    final repo = ref.read(recurringRepositoryProvider);
    if (_existing == null) {
      await repo.create(
        householdId: AppConstants.seedHouseholdId,
        userId: userId,
        kind: _kind,
        title: _titleController.text.trim(),
        amountPaise: money.paise,
        categoryId: _categoryId,
        paymentMethodId: _kind == TxnKind.expense ? _paymentMethodId : null,
        note: _noteController.text.trim(),
        frequency: _frequency,
        intervalN: _intervalN,
        dayOfMonth: dayOfMonth,
        startDate: _startDate,
        endDate: _endDate,
        autoPost: _autoPost,
      );
    } else {
      await repo.update(
        _existing!.copyWith(
          userId: userId,
          title: _titleController.text.trim(),
          amountPaise: money.paise,
          categoryId: _categoryId,
          paymentMethodId: _kind == TxnKind.expense ? _paymentMethodId : null,
          note: _noteController.text.trim(),
          frequency: _frequency,
          intervalN: _intervalN,
          dayOfMonth: dayOfMonth,
          endDate: _endDate,
          autoPost: _autoPost,
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
        title: const Text('Delete recurring rule?'),
        content: const Text(
          'This stops future occurrences. Transactions already posted are '
          'not affected.',
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
    );
    if (confirmed != true || !mounted) return;
    await ref.read(recurringRepositoryProvider).delete(widget.id!);
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

/// Non-owner, non-admin view of someone else's recurring rule (mirrors
/// `_ReadOnlyExpenseView`/`_ReadOnlyIncomeView`): shown, not editable.
class _ReadOnlyRecurringView extends StatelessWidget {
  const _ReadOnlyRecurringView({required this.rule});

  final domain.RecurringRule rule;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recurring')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(rule.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            rule.amount.format(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (rule.note.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(rule.note),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}
