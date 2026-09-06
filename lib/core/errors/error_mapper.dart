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
    if (error is SocketException || error is TimeoutException) {
      return const NetworkFailure();
    }
    if (error is AuthException) return AuthFailure(_authMessage(error));
    if (error is PostgrestException) return _postgrestFailure(error);
    if (error is StorageException) return const StorageFailure();
    return const UnknownFailure();
  }

  static String _authMessage(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Email or password is incorrect.';
    }
    if (msg.contains('email not confirmed')) {
      return 'This account has not been confirmed yet. Ask the admin to check it.';
    }
    // Sign-up errors (spec F-15, T-M2.4). `code` is the more reliable
    // signal where GoTrue sets one; the message check is a fallback for
    // whichever of the two doesn't line up across a GoTrue version bump.
    if (e.code == 'user_already_exists' ||
        msg.contains('already registered') ||
        msg.contains('already been registered')) {
      return 'That email already has an account — sign in instead?';
    }
    if (e.code == 'weak_password' || msg.contains('password should')) {
      return 'Choose a stronger password.';
    }
    if (e.code == 'over_email_send_rate_limit' ||
        e.code == 'over_request_rate_limit' ||
        e.statusCode == '429') {
      return 'Too many attempts. Try again in a few minutes.';
    }
    if (msg.contains('network')) {
      return 'No internet connection. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }

  static Failure _postgrestFailure(PostgrestException e) {
    // Postgres error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
    final code = e.code;
    final message = e.message.toLowerCase();

    // Every v2.0 membership RPC (spec §6.9.2, T-M2.3) signals a named
    // failure with a bare `raise exception '<code>'` — Postgres defaults
    // that to SQLSTATE P0001, with `message` set to exactly the code
    // string. Checked first: a bare P0001 carries none of the generic
    // signals (row-level security text, a constraint-violation code) the
    // checks below key on, so it would otherwise fall through to
    // UnknownFailure. (`household_id_immutable`/`role_immutable` — raised
    // by the `guard_profile_membership` trigger if something ever writes
    // `profiles.household_id`/`role` outside these RPCs — are deliberately
    // not mapped here: reaching the client at all would mean a client bug
    // calling the wrong write path, not a normal user-facing outcome.)
    if (code == 'P0001') {
      final named = _namedRpcFailure(message);
      if (named != null) return named;
    }

    if (code == '42501' ||
        message.contains('row-level security') ||
        message.contains('permission denied')) {
      return const PermissionFailure(
        'You can only edit expenses you added yourself.',
      );
    }
    if (code == '23505') {
      return const ValidationFailure('That name is already in use.');
    }
    if (code == '23514' || code == '23503' || code == '23502') {
      return const ValidationFailure('That value is not valid.');
    }
    return const UnknownFailure();
  }

  /// Copy for `already_in_household`/`invalid_invite`/`household_inactive`/
  /// `last_admin` is spec-exact (F-15/F-16). The rest have no literal quoted
  /// copy anywhere in the spec — only the bare code name, in the RPC bodies
  /// (§6.9.2) and the §7.2 cross-tenant test table — so their wording here
  /// is this task's own, chosen to match the spec's plain, direct tone.
  /// `promote_someone_first`'s spec copy embeds the household's name
  /// ("You're the only admin of \[name\]...") — dropped here since a
  /// static mapper has no household context; the calling screen (F-18) can
  /// prefix it if it wants to.
  static Failure? _namedRpcFailure(String message) {
    switch (message) {
      case 'already_in_household':
        return const ValidationFailure(
          "You're already in a household. Leave it first from Settings.",
        );
      case 'invalid_invite':
        return const ValidationFailure(
          "That code isn't valid any more. Ask for a fresh one.",
        );
      case 'household_inactive':
        return const ValidationFailure('That household is no longer active.');
      case 'last_admin':
        return const ValidationFailure(
          "You're the only admin. Make someone else an admin first.",
        );
      case 'promote_someone_first':
        return const ValidationFailure(
          "You're the only admin. Make someone else an admin, or remove "
          'the other members first.',
        );
      case 'not_admin':
        return const PermissionFailure('Only an admin can do that.');
      case 'not_a_member':
        return const ValidationFailure(
          'That person is no longer a member of this household.',
        );
      case 'not_in_household':
        return const ValidationFailure(
          'You need to be in a household to do that.',
        );
      case 'cannot_deactivate_self':
        return const ValidationFailure(
          "You can't deactivate your own account from here.",
        );
      case 'use_leave_household':
        return const ValidationFailure(
          'Use "Leave household" to remove yourself.',
        );
      case 'household_not_empty':
        return const ValidationFailure(
          "You can't delete a household while other members are still in "
          'it.',
        );
      default:
        return null;
    }
  }
}
