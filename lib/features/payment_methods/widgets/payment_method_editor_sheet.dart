import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../data/repositories/payment_method_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/payment_method.dart' as domain;

/// Create/edit sheet for one payment method (spec §11.5): name + type. No
/// icon/colour picker — `payment_methods` has no such columns; its icon is
/// derived from `type` (see [iconForPaymentMethodType]).
Future<void> showPaymentMethodEditorSheet(
  BuildContext context, {
  domain.PaymentMethod? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _PaymentMethodEditorSheet(existing: existing),
  );
}

class _PaymentMethodEditorSheet extends ConsumerStatefulWidget {
  const _PaymentMethodEditorSheet({this.existing});

  final domain.PaymentMethod? existing;

  @override
  ConsumerState<_PaymentMethodEditorSheet> createState() =>
      _PaymentMethodEditorSheetState();
}

class _PaymentMethodEditorSheetState
    extends ConsumerState<_PaymentMethodEditorSheet> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late PayMethodType _type = widget.existing?.type ?? PayMethodType.other;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Name is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(paymentMethodRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(
        householdId: AppConstants.seedHouseholdId,
        name: name,
        type: _type,
      );
    } else {
      await repo.update(widget.existing!.copyWith(name: name, type: _type));
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
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
            Text(
              isEdit ? 'Edit payment method' : 'New payment method',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: !isEdit,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _error,
              ),
              maxLength: 40,
            ),
            const SizedBox(height: 8),
            Text('Type', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in PayMethodType.values)
                  ChoiceChip(
                    label: Text(type.name),
                    avatar: Icon(iconForPaymentMethodType(type), size: 18),
                    selected: type == _type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),
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
          ],
        ),
      ),
    );
  }
}
