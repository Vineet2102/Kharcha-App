import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/widgets/colour_swatch_picker.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../domain/models/category.dart' as domain;
import '../../../domain/models/enums.dart';

/// Create/edit sheet for one category (spec §11.5): name, kind, icon,
/// colour. Kind is locked once a category exists — changing expense/income
/// after expenses have been tagged with it would silently reclassify them.
Future<void> showCategoryEditorSheet(
  BuildContext context, {
  domain.Category? existing,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CategoryEditorSheet(existing: existing),
  );
}

class _CategoryEditorSheet extends ConsumerStatefulWidget {
  const _CategoryEditorSheet({this.existing});

  final domain.Category? existing;

  @override
  ConsumerState<_CategoryEditorSheet> createState() =>
      _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends ConsumerState<_CategoryEditorSheet> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late CategoryKind _kind = widget.existing?.kind ?? CategoryKind.expense;
  late String _iconKey = widget.existing?.iconKey ?? 'category';
  late String _colourHex =
      widget.existing?.colourHex ?? categoryColourPalette.last;
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
    final repo = ref.read(categoryRepositoryProvider);
    if (widget.existing == null) {
      await repo.create(
        householdId: AppConstants.seedHouseholdId,
        name: name,
        kind: _kind,
        iconKey: _iconKey,
        colourHex: _colourHex,
      );
    } else {
      await repo.update(
        widget.existing!.copyWith(
          name: name,
          iconKey: _iconKey,
          colourHex: _colourHex,
        ),
      );
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
              isEdit ? 'Edit category' : 'New category',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: !isEdit,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
              maxLength: 40,
            ),
            const SizedBox(height: 8),
            SegmentedButton<CategoryKind>(
              segments: const [
                ButtonSegment(
                  value: CategoryKind.expense,
                  label: Text('Expense'),
                ),
                ButtonSegment(
                  value: CategoryKind.income,
                  label: Text('Income'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: isEdit
                  ? null
                  : (selection) => setState(() => _kind = selection.first),
            ),
            const SizedBox(height: 16),
            Text('Icon', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final entry in categoryIconOptions.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _IconChoice(
                        icon: entry.value,
                        selected: entry.key == _iconKey,
                        colour: colourFromHex(_colourHex),
                        onTap: () => setState(() => _iconKey = entry.key),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Text('Colour', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            ColourSwatchPicker(
              selectedHex: _colourHex,
              onSelected: (hex) => setState(() => _colourHex = hex),
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

class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.colour,
    required this.onTap,
  });

  final IconData icon;
  final bool selected;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24),
      child: CircleAvatar(
        radius: 24,
        backgroundColor: selected ? colour : colour.withValues(alpha: 0.15),
        foregroundColor: selected ? Colors.white : colour,
        child: Icon(icon),
      ),
    );
  }
}
