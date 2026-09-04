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

  Future<Result<void, Failure>> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email, password: password);
      return const Result.ok(null);
    } catch (error) {
      final failure = ErrorMapper.map(error);
      // Spec §11.1: sign-in needs a network connection the first time, and
      // that case gets its own message rather than the generic offline one.
      if (failure is NetworkFailure) {
        return const Result.err(
          NetworkFailure("You're offline. Sign in needs an internet connection the first time."),
        );
      }
      return Result.err(failure);
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
}

@Riverpod(keepAlive: true)
AuthRepository authRepository(Ref ref) => AuthRepository(ref.watch(supabaseClientProvider));
