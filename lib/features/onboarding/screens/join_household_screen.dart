import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../routing/routes.dart';
import '../controllers/join_household_controller.dart';

/// Uppercases as typed, strips anything but letters/digits (so pasting
/// "abcd efgh" or "abcd-efgh" both land the same), inserts the dash after
/// the 4th character, and caps at 8 significant characters (spec F-15
/// "Join").
class _InviteCodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    final truncated = raw.length > 8 ? raw.substring(0, 8) : raw;
    final buffer = StringBuffer();
    for (var i = 0; i < truncated.length; i++) {
      if (i == 4) buffer.write('-');
      buffer.write(truncated[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Join a household (spec F-15 "Join", T-M2.6).
class JoinHouseholdScreen extends ConsumerStatefulWidget {
  const JoinHouseholdScreen({super.key});

  @override
  ConsumerState<JoinHouseholdScreen> createState() =>
      _JoinHouseholdScreenState();
}

class _JoinHouseholdScreenState extends ConsumerState<JoinHouseholdScreen> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  bool get _codeComplete =>
      _codeController.text.replaceAll('-', '').length == 8;

  Future<void> _submit() async {
    if (!_codeComplete) return;
    FocusScope.of(context).unfocus();
    await ref
        .read(joinHouseholdControllerProvider.notifier)
        .join(_codeController.text.replaceAll('-', ''));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(joinHouseholdControllerProvider);
    final outcome = state.value;

    return Scaffold(
      appBar: AppBar(title: const Text('Join a household')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: outcome == null
                  ? _CodeForm(
                      controller: _codeController,
                      isLoading: state.isLoading,
                      error: state.hasError ? state.error as Failure : null,
                      canSubmit: _codeComplete,
                      onChanged: () => setState(() {}),
                      onSubmit: _submit,
                    )
                  : _Joined(householdName: outcome.name),
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeForm extends StatelessWidget {
  const _CodeForm({
    required this.controller,
    required this.isLoading,
    required this.error,
    required this.canSubmit,
    required this.onChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final bool isLoading;
  final Failure? error;
  final bool canSubmit;
  final VoidCallback onChanged;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          "Enter the 8-character code someone shared with you.",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: controller,
          textAlign: TextAlign.center,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: [_InviteCodeFormatter()],
          onChanged: (_) => onChanged(),
          onSubmitted: (_) => onSubmit(),
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(letterSpacing: 4),
          decoration: const InputDecoration(
            hintText: 'ABCD-EFGH',
            border: OutlineInputBorder(),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 16),
          Text(
            error!.message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: (isLoading || !canSubmit) ? null : onSubmit,
          child: isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Join'),
        ),
      ],
    );
  }
}

class _Joined extends StatelessWidget {
  const _Joined({required this.householdName});

  final String householdName;

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
          "You've joined $householdName",
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: () => context.go(AppRoutes.dashboard),
          child: const Text('Continue'),
        ),
      ],
    );
  }
}
