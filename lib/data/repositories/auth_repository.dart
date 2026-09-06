import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../remote/supabase_client_provider.dart';

part 'auth_repository.g.dart';

/// Wraps Supabase auth (spec §11.1, T-3.2). Never throws — every call maps
/// its outcome through [ErrorMapper] into a [Result].
class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Session? get currentSession => _client.auth.currentSession;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  Future<Result<void, Failure>> signIn({
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      return const Result.ok(null);
    } catch (error) {
      final failure = ErrorMapper.map(error);
      // Spec §11.1: sign-in needs a network connection the first time, and
      // that case gets its own message rather than the generic offline one.
      if (failure is NetworkFailure) {
        return const Result.err(
          NetworkFailure(
            "You're offline. Sign in needs an internet connection the first time.",
          ),
        );
      }
      return Result.err(failure);
    }
  }

  /// Sign-up (spec F-15, T-M2.4). `displayName` is passed as
  /// `raw_user_meta_data.display_name` so the server-side `handle_new_user`
  /// trigger picks it up for the new `profiles` row; the account starts
  /// with no household (v2.0's `handle_new_user`, unlike v1.0's, never
  /// auto-assigns one). Never signs the caller straight into the app —
  /// email confirmation is required first (T-M1.8), so a successful call
  /// here only means the account was created, not that it's usable yet.
  Future<Result<void, Failure>> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    try {
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {'display_name': displayName},
      );
      return const Result.ok(null);
    } catch (error) {
      final failure = ErrorMapper.map(error);
      if (failure is NetworkFailure) {
        return const Result.err(
          NetworkFailure('Creating an account needs an internet connection.'),
        );
      }
      return Result.err(failure);
    }
  }

  /// Re-sends the sign-up confirmation email (spec F-15 "Verify email",
  /// T-M2.5's Resend button). Distinct from [resetPassword]'s email — this
  /// one re-triggers the original confirmation link, not a password reset.
  Future<Result<void, Failure>> resendConfirmationEmail(String email) async {
    try {
      await _client.auth.resend(email: email, type: OtpType.signup);
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Best-effort poll for "has this account been confirmed yet?" (spec F-15
  /// "Verify email", T-M2.5: polled on resume and every 5s while that
  /// screen is visible). There is deliberately no [Result] here — every
  /// outcome short of "yes, refreshed" (no session to refresh yet, offline,
  /// a transient server error) means exactly one thing to the caller: keep
  /// waiting, nothing to show the user. A refreshed session fires
  /// `onAuthStateChange`, which the router's `redirect` already listens to
  /// (T-3.4) — this method's only job is to give that a chance to happen;
  /// it does not navigate anywhere itself.
  Future<bool> tryRefreshSession() async {
    try {
      await _client.auth.refreshSession();
      return _client.auth.currentSession != null;
    } catch (_) {
      return false;
    }
  }

  Future<Result<void, Failure>> signOut() async {
    try {
      await _client.auth.signOut();
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  Future<Result<void, Failure>> resetPassword(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(email);
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Change-password from within Settings (spec §11.13, T-14.2). Needs no
  /// current-password confirmation — Supabase's `updateUser` operates on
  /// the already-authenticated session, not a fresh credential check.
  Future<Result<void, Failure>> updatePassword(String newPassword) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: newPassword));
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) =>
    AuthRepository(ref.watch(supabaseClientProvider));
