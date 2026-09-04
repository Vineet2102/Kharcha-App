import 'package:flutter/material.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../core/time/app_time.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';
import '../../../domain/models/expense_filter.dart';
import '../../../domain/models/payment_method.dart' as domain;
import '../../../domain/models/profile.dart' as domain;

/// The Expense List's combinable filter sheet (spec §11.3, T-5.8): date
/// range, member(s), category(ies), payment method(s), amount range, only
/// mine / only with receipts.
Future<ExpenseFilter?> showExpenseFilterSheet(
  BuildContext context, {
  required ExpenseFilter initial,
  required List<domain.Category> categories,
  required List<domain.PaymentMethod> methods,
  required List<domain.Profile> profiles,
  required String? currentUserId,
}) {
  return showModalBottomSheet<ExpenseFilter>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ExpenseFilterSheet(
      initial: initial,
      categories: categories,
      methods: methods,
      profiles: profiles,
      currentUserId: currentUserId,
    ),
  );
}

class _ExpenseFilterSheet extends StatefulWidget {
  const _ExpenseFilterSheet({
    required this.initial,
    required this.categories,
    required this.methods,
    required this.profiles,
    required this.currentUserId,
  });

  final ExpenseFilter initial;
  final List<domain.Category> categories;
  final List<domain.PaymentMethod> methods;
  final List<domain.Profile> profiles;
  final String? currentUserId;

  @override
  State<_ExpenseFilterSheet> createState() => _ExpenseFilterSheetState();
}

class _ExpenseFilterSheetState extends State<_ExpenseFilterSheet> {
  late DateTime? _startDate = widget.initial.startDate;
  late DateTime? _endDate = widget.initial.endDate;
  late final Set<String> _memberIds = {...widget.initial.memberIds};
  late final Set<String> _categoryIds = {...widget.initial.categoryIds};
  late final Set<String> _paymentMethodIds = {...widget.initial.paymentMethodIds};
  late final _minController = TextEditingController(
    text: widget.initial.minAmountPaise == null
        ? ''
        : (widget.initial.minAmountPaise! / 100).toStringAsFixed(0),
  );
  late final _maxController = TextEditingController(
    text: widget.initial.maxAmountPaise == null
        ? ''
        : (widget.initial.maxAmountPaise! / 100).toStringAsFixed(0),
  );
  late bool _onlyWithReceipts = widget.initial.onlyWithReceipts;

  bool get _onlyMine =>
      widget.currentUserId != null &&
      _memberIds.length == 1 &&
      _memberIds.single == widget.currentUserId;

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Filters', style: Theme.of(context).textTheme.titleLarge),
                TextButton(onPressed: _reset, child: const Text('Reset')),
              ],
            ),
            const SizedBox(height: 8),
            Text('Date range', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('This month'),
                  selected: _isThisMonth,
                  onSelected: (_) => setState(() {
                    final start = AppTime.monthStart(DateTime.now().toUtc());
                    _startDate = start;
                    _endDate = AppTime.monthAfter(
                      start,
                      1,
                    ).subtract(const Duration(days: 1));
                  }),
                ),
                ChoiceChip(
                  label: const Text('All time'),
                  selected: _startDate == null && _endDate == null,
                  onSelected: (_) => setState(() {
                    _startDate = null;
                    _endDate = null;
                  }),
                ),
                ActionChip(
                  label: const Text('Custom range'),
                  onPressed: _pickCustomRange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only mine'),
              value: _onlyMine,
              onChanged: widget.currentUserId == null
                  ? null
                  : (value) => setState(() {
                      if (value) {
                        _memberIds
                          ..clear()
                          ..add(widget.currentUserId!);
                      } else {
                        _memberIds.clear();
                      }
                    }),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Only with receipts'),
              value: _onlyWithReceipts,
              onChanged: (value) => setState(() => _onlyWithReceipts = value),
            ),
            if (!_onlyMine && widget.profiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Member', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final profile in widget.profiles)
                    FilterChip(
                      label: Text(profile.displayName),
                      selected: _memberIds.contains(profile.id),
                      onSelected: (selected) => setState(() {
                        selected
                            ? _memberIds.add(profile.id)
                            : _memberIds.remove(profile.id);
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Text('Category', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final category in widget.categories.where(
                  (c) => c.kind == CategoryKind.expense,
                ))
                  FilterChip(
                    avatar: Icon(iconForKey(category.iconKey), size: 18),
                    label: Text(category.name),
                    selected: _categoryIds.contains(category.id),
                    onSelected: (selected) => setState(() {
                      selected
                          ? _categoryIds.add(category.id)
                          : _categoryIds.remove(category.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Payment method',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final method in widget.methods)
                  FilterChip(
                    avatar: Icon(iconForPaymentMethodType(method.type), size: 18),
                    label: Text(method.name),
                    selected: _paymentMethodIds.contains(method.id),
                    onSelected: (selected) => setState(() {
                      selected
                          ? _paymentMethodIds.add(method.id)
                          : _paymentMethodIds.remove(method.id);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Amount range (₹)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Min'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _maxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(_buildFilter()),
              child: const Text('Apply filters'),
            ),
          ],
        ),
      ),
    );
  }

  bool get _isThisMonth {
    if (_startDate == null || _endDate == null) return false;
    final expectedStart = AppTime.monthStart(DateTime.now().toUtc());
    return _startDate!.isAtSameMomentAs(expectedStart);
  }

  Future<void> _pickCustomRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _startDate != null && _endDate != null
          ? DateTimeRange(start: _startDate!.toLocal(), end: _endDate!.toLocal())
          : null,
    );
    if (range == null) return;
    setState(() {
      _startDate = AppTime.calendarDate(range.start);
      _endDate = AppTime.calendarDate(range.end);
    });
  }

  void _reset() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _memberIds.clear();
      _categoryIds.clear();
      _paymentMethodIds.clear();
      _minController.clear();
      _maxController.clear();
      _onlyWithReceipts = false;
    });
  }

  ExpenseFilter _buildFilter() {
    final min = int.tryParse(_minController.text.trim());
    final max = int.tryParse(_maxController.text.trim());
    return ExpenseFilter(
      startDate: _startDate,
      endDate: _endDate,
      memberIds: _memberIds.toList(),
      categoryIds: _categoryIds.toList(),
      paymentMethodIds: _paymentMethodIds.toList(),
      minAmountPaise: min == null ? null : min * 100,
      maxAmountPaise: max == null ? null : max * 100,
      onlyWithReceipts: _onlyWithReceipts,
      searchText: widget.initial.searchText,
    );
  }
}
