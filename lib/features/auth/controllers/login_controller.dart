import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../data/repositories/auth_repository.dart';

part 'login_controller.g.dart';

/// Drives the login screen (spec §11.1, T-3.3). `state` is `AsyncError`
/// after a failed sign-in, carrying the [Failure] to show inline.
///
/// `keepAlive: true` because a successful sign-in fires the router redirect
/// (T-3.4) immediately, unmounting `LoginScreen` while `signIn()` is still
/// running its final `state = ...` assignment — an auto-dispose provider
/// would already be torn down by then and throw on that write.
@Riverpod(keepAlive: true)
class LoginController extends _$LoginController {
  @override
  FutureOr<void> build() {}

  Future<bool> signIn({required String email, required String password}) async {
    state = const AsyncLoading();
    final result = await ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password);
    return result.fold(
      (_) {
        state = const AsyncData(null);
        return true;
      },
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
    );
  }

  Future<Result<void, Failure>> sendPasswordReset(String email) {
    return ref.read(authRepositoryProvider).resetPassword(email);
  }
}
