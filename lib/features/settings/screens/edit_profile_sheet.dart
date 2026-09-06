import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/colour_swatch_picker.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/profile.dart' as domain;

/// Self-edit: display name + avatar colour (spec §11.13 "Profile" section,
/// T-14.2). Mirrors `category_editor_sheet.dart`'s shape.
Future<void> showEditProfileSheet(BuildContext context, domain.Profile profile) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditProfileSheet(profile: profile),
  );
}

class _EditProfileSheet extends ConsumerStatefulWidget {
  const _EditProfileSheet({required this.profile});

  final domain.Profile profile;

  @override
  ConsumerState<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends ConsumerState<_EditProfileSheet> {
  late final _nameController = TextEditingController(
    text: widget.profile.displayName,
  );
  late String _colourHex = widget.profile.colourHex;
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
    final repo = ref.read(profileRepositoryProvider);
    if (name != widget.profile.displayName) {
      await repo.updateDisplayName(widget.profile.id, name);
    }
    if (_colourHex != widget.profile.colourHex) {
      await repo.updateColourHex(widget.profile.id, _colourHex);
    }
    if (mounted) Navigator.of(context).pop();
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
            Text('Edit profile', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Display name',
                errorText: _error,
              ),
              maxLength: 40,
            ),
            const SizedBox(height: 8),
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
