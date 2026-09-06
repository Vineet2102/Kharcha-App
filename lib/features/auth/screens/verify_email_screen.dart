import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/auth_repository.dart';
import '../../../routing/routes.dart';

/// Verify email (spec F-15, T-M2.5). Reached only from `SignUpScreen`'s
/// success path, which passes the just-registered address as `extra` —
/// there is no session at all yet (confirm-email is mandatory, T-M1.8), so
/// there is nowhere else this screen could read it from.
class VerifyEmailScreen extends ConsumerStatefulWidget {
  const VerifyEmailScreen({super.key, this.email});

  final String? email;

  @override
  ConsumerState<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends ConsumerState<VerifyEmailScreen>
    with WidgetsBindingObserver {
  static const _resendCooldown = Duration(seconds: 60);
  static const _pollInterval = Duration(seconds: 5);

  Timer? _pollTimer;
  Timer? _cooldownTicker;
  int _cooldownSeconds = 0;
  bool _resending = false;
  bool _checkingConfirmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkConfirmed());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _cooldownTicker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkConfirmed();
  }

  /// Swallows every outcome except "confirmed" — see
  /// `AuthRepository.tryRefreshSession`'s own doc comment for why this is
  /// deliberately silent rather than surfacing an error on every poll tick
  /// that isn't the one that matters.
  Future<void> _checkConfirmed() async {
    if (_checkingConfirmed || !mounted) return;
    _checkingConfirmed = true;
    await ref.read(authRepositoryProvider).tryRefreshSession();
    _checkingConfirmed = false;
  }

  Future<void> _resend() async {
    final email = widget.email;
    if (email == null || _cooldownSeconds > 0 || _resending) return;
    setState(() => _resending = true);
    final result = await ref
        .read(authRepositoryProvider)
        .resendConfirmationEmail(email);
    if (!mounted) return;
    setState(() => _resending = false);
    result.fold((_) => _startCooldown(), (failure) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    });
  }

  void _startCooldown() {
    setState(() => _cooldownSeconds = _resendCooldown.inSeconds);
    _cooldownTicker?.cancel();
    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds -= 1;
        if (_cooldownSeconds <= 0) timer.cancel();
      });
    });
  }

  /// "Wrong address?" (spec F-15): the account that was just created under
  /// the typo'd address can't be fixed in place — there's no session to
  /// edit it with — so this signs out (a harmless no-op if no session ever
  /// existed) and sends the user back to create a fresh account with the
  /// correct address. The orphaned unconfirmed account is left behind;
  /// nothing else in the app ever references it.
  Future<void> _wrongAddress() async {
    await ref.read(authRepositoryProvider).signOut();
    if (mounted) context.go(AppRoutes.signup);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.mark_email_unread_outlined, size: 64),
                  const SizedBox(height: 24),
                  Text(
                    widget.email == null
                        ? "We've sent you a confirmation link."
                        : "We've sent a confirmation link to ${widget.email}.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap the link on this phone to continue — you don\'t '
                    'need to come back to this screen.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Check your spam folder',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  FilledButton(
                    onPressed:
                        (widget.email == null ||
                            _resending ||
                            _cooldownSeconds > 0)
                        ? null
                        : _resend,
                    child: _resending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _cooldownSeconds > 0
                                ? 'Resend in ${_cooldownSeconds}s'
                                : 'Resend email',
                          ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _wrongAddress,
                    child: const Text('Wrong address? Start again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
