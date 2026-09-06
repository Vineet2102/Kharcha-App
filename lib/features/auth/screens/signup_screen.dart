import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../routing/routes.dart';
import '../controllers/signup_controller.dart';

final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// Sign-up (spec F-15, T-M2.4). On success, hands off to `/verify-email` —
/// never straight into the app; email confirmation is mandatory (D2).
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final email = _emailController.text.trim().toLowerCase();
    final success = await ref
        .read(signUpControllerProvider.notifier)
        .signUp(
          displayName: _nameController.text.trim(),
          email: email,
          password: _passwordController.text,
        );
    if (success && mounted) {
      context.go(AppRoutes.verifyEmail, extra: email);
    }
  }

  void _showNotPublishedYet(String what) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text("The $what aren't published yet.")));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(signUpControllerProvider);
    final isLoading = state.isLoading;
    final error = state.hasError ? state.error as Failure : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameController,
                      autofillHints: const [AutofillHints.name],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'Display name',
                      ),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return 'Enter your name.';
                        if (trimmed.length < 2 || trimmed.length > 40) {
                          return 'Name must be 2–40 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (value) {
                        final trimmed = value?.trim() ?? '';
                        if (trimmed.isEmpty) return 'Enter your email.';
                        if (!_emailRegex.hasMatch(trimmed)) {
                          return 'Enter a valid email.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      autofillHints: const [AutofillHints.newPassword],
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: 'Password',
                        helperText: 'At least 8 characters.',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Enter a password.';
                        }
                        if (value.length < 8) {
                          return 'Password must be at least 8 characters.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscureConfirm,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Confirm password',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'Passwords do not match.';
                        }
                        return null;
                      },
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        error.message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isLoading ? null : _submit,
                      child: isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Create account'),
                    ),
                    const SizedBox(height: 12),
                    // Spec F-15: a checkbox is deliberately not used for
                    // legal consent — the button above already commits the
                    // user, and "Terms"/"Privacy Policy" are individually
                    // tappable rather than one plain sentence.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'By creating an account you agree to the ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        InkWell(
                          onTap: () => _showNotPublishedYet('Terms'),
                          child: Text(
                            'Terms',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  decoration: TextDecoration.underline,
                                ),
                          ),
                        ),
                        Text(
                          ' and ',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        InkWell(
                          onTap: () => _showNotPublishedYet('Privacy Policy'),
                          child: Text(
                            'Privacy Policy',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  decoration: TextDecoration.underline,
                                ),
                          ),
                        ),
                        Text('.', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
