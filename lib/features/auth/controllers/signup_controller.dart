import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/auth_repository.dart';

part 'signup_controller.g.dart';

/// Drives the sign-up screen (spec F-15, T-M2.4). `state` is `AsyncError`
/// after a failed sign-up, carrying the `Failure` to show inline — same
/// shape as `LoginController`.
///
/// `keepAlive: true` for the same reason as `LoginController`: most
/// Supabase projects never establish a session from `signUp()` while email
/// confirmation is required (T-M1.8), but a project where it's off would
/// fire the router's auth-state redirect mid-`await`, and an auto-dispose
/// provider would already be torn down by the time this method's final
/// `state = ...` runs.
@Riverpod(keepAlive: true)
class SignUpController extends _$SignUpController {
  @override
  FutureOr<void> build() {}

  Future<bool> signUp({
    required String displayName,
    required String email,
    required String password,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .read(authRepositoryProvider)
        .signUp(displayName: displayName, email: email, password: password);
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
}
