import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/errors/failure.dart';
import '../../../data/repositories/household_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../routing/routes.dart';
import '../controllers/create_household_controller.dart';

/// Create a household (spec F-15 "Create", T-M2.6). One field, prefilled so
/// a solo user can just press Continue; on success the same screen flips to
/// the invite-code reveal rather than navigating to a separate route — the
/// spec's own route map (§10.1) has no further route for it, and the code
/// only exists at all once creation has already succeeded.
class CreateHouseholdScreen extends ConsumerStatefulWidget {
  const CreateHouseholdScreen({super.key});

  @override
  ConsumerState<CreateHouseholdScreen> createState() =>
      _CreateHouseholdScreenState();
}

class _CreateHouseholdScreenState extends ConsumerState<CreateHouseholdScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  bool _prefilled = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _prefillIfNeeded(String? displayName) {
    if (_prefilled || _nameController.text.isNotEmpty) return;
    if (displayName == null || displayName.isEmpty) return;
    _prefilled = true;
    _nameController.text = "$displayName's household";
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(createHouseholdControllerProvider.notifier)
        .create(_nameController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final displayName = ref.watch(currentProfileProvider).value?.displayName;
    _prefillIfNeeded(displayName);

    final state = ref.watch(createHouseholdControllerProvider);
    final outcome = state.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Create a household')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: outcome == null
                  ? _NameForm(
                      formKey: _formKey,
                      nameController: _nameController,
                      isLoading: state.isLoading,
                      error: state.hasError ? state.error as Failure : null,
                      onSubmit: _submit,
                    )
                  : _InviteCodeReveal(outcome: outcome),
            ),
          ),
        ),
      ),
    );
  }
}

class _NameForm extends StatelessWidget {
  const _NameForm({
    required this.formKey,
    required this.nameController,
    required this.isLoading,
    required this.error,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final bool isLoading;
  final Failure? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: nameController,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => onSubmit(),
            decoration: const InputDecoration(labelText: 'Household name'),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return 'Enter a household name.';
              if (trimmed.length > 60) {
                return 'Household name must be 60 characters or fewer.';
              }
              return null;
            },
          ),
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error!.message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: isLoading ? null : onSubmit,
            child: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}

class _InviteCodeReveal extends StatelessWidget {
  const _InviteCodeReveal({required this.outcome});

  final CreateHouseholdOutcome outcome;

  String get _formattedCode {
    final code = outcome.inviteCode;
    if (code.length != 8) return code;
    return '${code.substring(0, 4)}-${code.substring(4)}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 48,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          '${outcome.name} is ready',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Share this code so others can join.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        SelectableText(
          _formattedCode,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall
              ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 4),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _formattedCode));
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Code copied')));
                }
              },
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: () => SharePlus.instance.share(
                ShareParams(
                  text:
                      'Join my household on Kharcha! Enter this code when '
                      'you sign up: $_formattedCode',
                ),
              ),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
          ],
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.go(AppRoutes.dashboard),
          child: const Text("I'll do this later"),
        ),
      ],
    );
  }
}
