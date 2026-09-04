import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'failure.dart';

/// Converts any exception the app might catch into a [Failure] carrying a
/// human-readable, Indian-English message. Never let a raw exception string
/// reach the UI — log the detail with `AppLogger` instead (spec §9.7).
class ErrorMapper {
  const ErrorMapper._();

  static Failure map(Object error) {
    if (error is Failure) return error;
    if (error is SocketException || error is TimeoutException) return const NetworkFailure();
    if (error is AuthException) return AuthFailure(_authMessage(error));
    if (error is PostgrestException) return _postgrestFailure(error);
    if (error is StorageException) return const StorageFailure();
    return const UnknownFailure();
  }

  static String _authMessage(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('email not confirmed')) {
      return 'This account has not been confirmed yet. Ask the admin to check it.';
    }
    if (msg.contains('network')) {
      return 'No internet connection. Please try again.';
    }
    return 'Could not sign in. Please try again.';
  }

  static Failure _postgrestFailure(PostgrestException e) {
    // Postgres error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
    final code = e.code;
    final message = e.message.toLowerCase();
    if (code == '42501' || message.contains('row-level security') || message.contains('permission denied')) {
      return const PermissionFailure('You can only edit expenses you added yourself.');
    }
    if (code == '23505') {
      return const ValidationFailure('That name is already in use.');
    }
    if (code == '23514' || code == '23503' || code == '23502') {
      return const ValidationFailure('That value is not valid.');
    }
    return const UnknownFailure();
  }
}
