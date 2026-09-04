import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../data/remote/supabase_client_provider.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/expense_repository.dart';
import '../../../data/repositories/payment_method_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/expense.dart' as domain;
import '../../../domain/models/payment_method.dart' as domain;
import '../../../domain/models/profile.dart' as domain;
import '../../shell/widgets/placeholder_screen.dart';

/// Add/Edit Expense (spec §11.2, T-5.5/T-5.6/T-5.9). `id` is null for the
/// "new" route. For an existing expense the signed-in member can only edit
/// if they own it or are an admin (T-5.9) — everyone else gets a read-only
/// view.
class ExpenseDetailScreen extends ConsumerStatefulWidget {
  const ExpenseDetailScreen({super.key, this.id, this.duplicateFrom});

  final String? id;

  /// Set when opened via the Expense List's swipe-right "Duplicate" action
  /// (spec §11.3) — pre-fills the new form's amount/category/payment
  /// method/note/merchant from this expense, but the date defaults to now.
  final domain.Expense? duplicateFrom;

  @override
  ConsumerState<ExpenseDetailScreen> createState() =>
      _ExpenseDetailScreenState();
}

class _ExpenseDetailScreenState extends ConsumerState<ExpenseDetailScreen> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _merchantController = TextEditingController();

  domain.Expense? _existing;
  bool _loading = true;
  bool _saving = false;

  String? _categoryId;
  String? _paymentMethodId;
  String? _paidByUserId;
  DateTime _spentAt = DateTime.now().toUtc();
  String? _amountError;

  List<String> _mostUsedCategoryIds = const [];
  List<String> _recentNotes = const [];
  List<String> _recentMerchants = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    _merchantController.dispose();
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
    final repo = ref.read(expenseRepositoryProvider);

    if (widget.id != null) {
      final expense = await repo.findById(widget.id!);
      if (expense != null) {
        _existing = expense;
        _amountController.text = expense.amount.rupees.toStringAsFixed(2);
        _noteController.text = expense.note;
        _merchantController.text = expense.merchant;
        _categoryId = expense.categoryId;
        _paymentMethodId = expense.paymentMethodId;
        _paidByUserId = expense.userId;
        _spentAt = expense.spentAt;
      }
    } else if (widget.duplicateFrom != null) {
      final source = widget.duplicateFrom!;
      _paidByUserId = userId;
      _amountController.text = source.amount.rupees.toStringAsFixed(2);
      _noteController.text = source.note;
      _merchantController.text = source.merchant;
      _categoryId = source.categoryId;
      _paymentMethodId = source.paymentMethodId;
    } else {
      _paidByUserId = userId;
      _paymentMethodId = userId == null
          ? null
          : await repo.lastUsedPaymentMethodId(userId);
    }

    if (userId != null) {
      _mostUsedCategoryIds = await repo.mostUsedCategoryIds(userId);
      _recentNotes = await repo.recentDistinctNotes(userId);
      _recentMerchants = await repo.recentDistinctMerchants(userId);
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.id == null ? 'Add expense' : 'Expense')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (widget.id != null && _existing == null) {
      return const PlaceholderScreen(title: 'Expense not found');
    }

    final categoriesAsync = ref.watch(categoriesProvider);
    final methodsAsync = ref.watch(paymentMethodsProvider);
    final profilesAsync = ref.watch(householdProfilesProvider);

    if (!_canEdit) {
      return _ReadOnlyExpenseView(
        expense: _existing!,
        categories: categoriesAsync.value ?? const [],
        methods: methodsAsync.value ?? const [],
        payer: profilesAsync.value?.firstWhere(
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
        .where((c) => c.kind == CategoryKind.expense && !c.isArchived)
        .toList();
    final methods = (methodsAsync.value ?? const <domain.PaymentMethod>[])
        .where((m) => !m.isArchived)
        .toList();
    final profiles = profilesAsync.value ?? const <domain.Profile>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.id == null ? 'Add expense' : 'Edit expense'),
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
          _AmountField(
            controller: _amountController,
            errorText: _amountError,
          ),
          const SizedBox(height: 24),
          Text('Category', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _CategoryChips(
            categories: categories,
            mostUsedIds: _mostUsedCategoryIds,
            selectedId: _categoryId,
            onSelected: (id) => setState(() => _categoryId = id),
          ),
          const SizedBox(height: 24),
          Text('Payment method', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _PaymentMethodChips(
            methods: methods,
            selectedId: _paymentMethodId,
            onSelected: (id) => setState(() => _paymentMethodId = id),
          ),
          const SizedBox(height: 24),
          Text('Date & time', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          _DateTimePicker(
            spentAt: _spentAt,
            onChanged: (value) => setState(() => _spentAt = value),
          ),
          const SizedBox(height: 24),
          _AutocompleteField(
            controller: _noteController,
            label: 'Note',
            maxLength: 200,
            suggestions: _recentNotes,
          ),
          const SizedBox(height: 16),
          _AutocompleteField(
            controller: _merchantController,
            label: 'Merchant',
            maxLength: 100,
            suggestions: _recentMerchants,
          ),
          if (_isAdmin && profiles.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Paid by', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final profile in profiles)
                  ChoiceChip(
                    label: Text(profile.displayName),
                    selected: profile.id == _paidByUserId,
                    onSelected: (_) =>
                        setState(() => _paidByUserId = profile.id),
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
    if (_categoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick a category.')));
      return;
    }
    if (_paymentMethodId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pick a payment method.')));
      return;
    }
    final tomorrow = DateTime.now().toUtc().add(const Duration(days: 1));
    if (_spentAt.isAfter(tomorrow)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Date cannot be more than 1 day in the future.'),
        ),
      );
      return;
    }

    final userId = _paidByUserId ?? _currentUserId;
    if (userId == null) return;

    setState(() {
      _saving = true;
      _amountError = null;
    });

    final repo = ref.read(expenseRepositoryProvider);
    final isDuplicate = await repo.hasPossibleDuplicate(
      householdId: AppConstants.seedHouseholdId,
      userId: userId,
      amountPaise: money.paise,
      categoryId: _categoryId,
      spentAt: _spentAt,
      excludingId: _existing?.id,
    );
    if (isDuplicate && mounted) {
      final proceed = await _confirmDuplicate();
      if (proceed != true) {
        setState(() => _saving = false);
        return;
      }
    }

    if (_existing == null) {
      final id = await repo.create(
        householdId: AppConstants.seedHouseholdId,
        userId: userId,
        amountPaise: money.paise,
        categoryId: _categoryId,
        paymentMethodId: _paymentMethodId,
        spentAt: _spentAt,
        note: _noteController.text.trim(),
        merchant: _merchantController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      _showSavedSnackbar(id);
    } else {
      await repo.update(
        _existing!.copyWith(
          userId: userId,
          amountPaise: money.paise,
          categoryId: _categoryId,
          paymentMethodId: _paymentMethodId,
          spentAt: _spentAt,
          note: _noteController.text.trim(),
          merchant: _merchantController.text.trim(),
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    }
  }

  /// Shows the 5 s Undo snackbar (spec §11.2, T-5.6) on the *previous*
  /// screen — this screen has already popped by the time the write lands.
  ///
  /// The explicit `Future.delayed` + `close()` is deliberate: Flutter's
  /// built-in `SnackBar.duration` is silently ignored whenever the device
  /// has accessible navigation on (e.g. TalkBack) — it waits for a manual
  /// dismiss instead, which otherwise leaves this snackbar on screen
  /// indefinitely. Forcing the close guarantees the same 5s window on every
  /// device.
  void _showSavedSnackbar(String expenseId) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final controller = messenger.showSnackBar(
      SnackBar(
        content: const Text('Saved ✓'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              ref.read(expenseRepositoryProvider).undoCreate(expenseId),
        ),
      ),
    );
    Future.delayed(const Duration(seconds: 5), controller.close);
  }

  Future<bool?> _confirmDuplicate() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Possible duplicate'),
        content: const Text(
          'Looks like a possible duplicate — save anyway?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save anyway'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true || !mounted) return;
    await ref.read(expenseRepositoryProvider).delete(widget.id!);
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

class _CategoryChips extends StatefulWidget {
  const _CategoryChips({
    required this.categories,
    required this.mostUsedIds,
    required this.selectedId,
    required this.onSelected,
  });

  final List<domain.Category> categories;
  final List<String> mostUsedIds;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  State<_CategoryChips> createState() => _CategoryChipsState();
}

class _CategoryChipsState extends State<_CategoryChips> {
  bool _showAll = false;

  @override
  Widget build(BuildContext context) {
    final byId = {for (final c in widget.categories) c.id: c};
    var visible = [
      for (final id in widget.mostUsedIds)
        if (byId[id] != null) byId[id]!,
    ];
    // If the currently selected category isn't in the "most used" set (e.g.
    // editing an old expense), make sure it's still visible without forcing
    // "More".
    final selected = widget.selectedId == null ? null : byId[widget.selectedId];
    if (selected != null && !visible.any((c) => c.id == selected.id)) {
      visible = [selected, ...visible];
    }
    if (visible.length > 8) visible = visible.sublist(0, 8);
    if (_showAll) visible = widget.categories;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final category in visible)
          ChoiceChip(
            avatar: Icon(iconForKey(category.iconKey), size: 18),
            label: Text(category.name),
            selected: category.id == widget.selectedId,
            onSelected: (_) => widget.onSelected(category.id),
          ),
        if (!_showAll && widget.categories.length > visible.length)
          ActionChip(
            label: const Text('More'),
            onPressed: () => setState(() => _showAll = true),
          ),
      ],
    );
  }
}

class _PaymentMethodChips extends StatelessWidget {
  const _PaymentMethodChips({
    required this.methods,
    required this.selectedId,
    required this.onSelected,
  });

  final List<domain.PaymentMethod> methods;
  final String? selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final method in methods)
          ChoiceChip(
            avatar: Icon(iconForPaymentMethodType(method.type), size: 18),
            label: Text(method.name),
            selected: method.id == selectedId,
            onSelected: (_) => onSelected(method.id),
          ),
      ],
    );
  }
}

class _DateTimePicker extends StatelessWidget {
  const _DateTimePicker({required this.spentAt, required this.onChanged});

  final DateTime spentAt;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final local = spentAt.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final isToday =
        local.year == today.year &&
        local.month == today.month &&
        local.day == today.day;
    final yesterday = today.subtract(const Duration(days: 1));
    final isYesterday =
        local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;

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
        ChoiceChip(
          label: const Text('Yesterday'),
          selected: isYesterday,
          onSelected: (_) => onChanged(
            DateTime(
              yesterday.year,
              yesterday.month,
              yesterday.day,
              local.hour,
              local.minute,
            ).toUtc(),
          ),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined, size: 16),
          label: Text(
            '${local.day}/${local.month}/${local.year} '
            '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}',
          ),
          onPressed: () => _pick(context),
        ),
      ],
    );
  }

  Future<void> _pick(BuildContext context) async {
    final local = spentAt.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    if (time == null) return;
    onChanged(
      DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc(),
    );
  }
}

class _AutocompleteField extends StatefulWidget {
  const _AutocompleteField({
    required this.controller,
    required this.label,
    required this.maxLength,
    required this.suggestions,
  });

  final TextEditingController controller;
  final String label;
  final int maxLength;
  final List<String> suggestions;

  @override
  State<_AutocompleteField> createState() => _AutocompleteFieldState();
}

class _AutocompleteFieldState extends State<_AutocompleteField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (value.text.isEmpty) return const Iterable.empty();
        final query = value.text.toLowerCase();
        return widget.suggestions.where(
          (s) => s.toLowerCase().contains(query),
        );
      },
      fieldViewBuilder: (context, textController, focusNode, onSubmit) {
        return TextField(
          controller: textController,
          focusNode: focusNode,
          maxLength: widget.maxLength,
          decoration: InputDecoration(labelText: widget.label),
        );
      },
      optionsViewBuilder: (context, onSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          child: SizedBox(
            width: 300,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final option in options)
                  ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Non-owner, non-admin view of someone else's expense (spec §11.9's
/// sibling rule for T-5.9): every field is shown, nothing is editable.
class _ReadOnlyExpenseView extends StatelessWidget {
  const _ReadOnlyExpenseView({
    required this.expense,
    required this.categories,
    required this.methods,
    required this.payer,
  });

  final domain.Expense expense;
  final List<domain.Category> categories;
  final List<domain.PaymentMethod> methods;
  final domain.Profile? payer;

  @override
  Widget build(BuildContext context) {
    domain.Category? category;
    for (final c in categories) {
      if (c.id == expense.categoryId) category = c;
    }
    domain.PaymentMethod? method;
    for (final m in methods) {
      if (m.id == expense.paymentMethodId) method = m;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Expense')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            expense.amount.format(),
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 16),
          if (category != null)
            ListTile(
              leading: Icon(iconForKey(category.iconKey)),
              title: Text(category.name),
              contentPadding: EdgeInsets.zero,
            ),
          if (method != null)
            ListTile(
              leading: Icon(iconForPaymentMethodType(method.type)),
              title: Text(method.name),
              contentPadding: EdgeInsets.zero,
            ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: Text(payer?.displayName ?? 'Unknown'),
            contentPadding: EdgeInsets.zero,
          ),
          if (expense.note.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: Text(expense.note),
              contentPadding: EdgeInsets.zero,
            ),
          if (expense.merchant.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: Text(expense.merchant),
              contentPadding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}
