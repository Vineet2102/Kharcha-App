import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/errors/error_mapper.dart';
import 'package:kharcha/core/errors/failure.dart';

void main() {
  group('ErrorMapper.map', () {
    test('passes an existing Failure through unchanged', () {
      const failure = ValidationFailure('bad input');
      expect(ErrorMapper.map(failure), same(failure));
    });

    test('maps an RLS denial to PermissionFailure', () {
      const error = PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      );
      expect(ErrorMapper.map(error), isA<PermissionFailure>());
    });

    test('maps a unique-violation to ValidationFailure', () {
      const error = PostgrestException(
        message: 'duplicate key value violates unique constraint',
        code: '23505',
      );
      expect(ErrorMapper.map(error), isA<ValidationFailure>());
    });

    test('maps an unrecognised Postgrest error code to UnknownFailure', () {
      const error = PostgrestException(
        message: 'something else',
        code: '99999',
      );
      expect(ErrorMapper.map(error), isA<UnknownFailure>());
    });

    test('maps invalid login credentials to a friendly AuthFailure', () {
      const error = AuthException('Invalid login credentials');
      final mapped = ErrorMapper.map(error);
      expect(mapped, isA<AuthFailure>());
      expect(mapped.message, 'Email or password is incorrect.');
    });

    // T-M2.4: sign-up-specific AuthExceptions (spec F-15).
    test('maps an already-registered email by its code', () {
      const error = AuthException(
        'A user with this email address has already been registered',
        code: 'user_already_exists',
      );
      final mapped = ErrorMapper.map(error);
      expect(mapped, isA<AuthFailure>());
      expect(
        mapped.message,
        "That email already has an account — sign in instead?",
      );
    });

    test('maps an already-registered email by message when code is absent', () {
      const error = AuthException('User already registered');
      final mapped = ErrorMapper.map(error);
      expect(
        mapped.message,
        "That email already has an account — sign in instead?",
      );
    });

    test('maps a weak-password rejection', () {
      const error = AuthException(
        'Password should be at least 8 characters',
        code: 'weak_password',
      );
      final mapped = ErrorMapper.map(error);
      expect(mapped, isA<AuthFailure>());
      expect(mapped.message, 'Choose a stronger password.');
    });

    test('maps a sign-up rate limit by code', () {
      const error = AuthException(
        'Email rate limit exceeded',
        code: 'over_email_send_rate_limit',
      );
      final mapped = ErrorMapper.map(error);
      expect(mapped.message, 'Too many attempts. Try again in a few minutes.');
    });

    test(
      'maps a sign-up rate limit by HTTP 429 status when code is absent',
      () {
        const error = AuthException('Too many requests', statusCode: '429');
        final mapped = ErrorMapper.map(error);
        expect(
          mapped.message,
          'Too many attempts. Try again in a few minutes.',
        );
      },
    );

    test(
      'falls back to a generic message for an unrecognised AuthException',
      () {
        const error = AuthException('some new GoTrue error we do not know');
        final mapped = ErrorMapper.map(error);
        expect(mapped.message, 'Something went wrong. Please try again.');
      },
    );

    test('maps an unrecognised object to UnknownFailure', () {
      expect(ErrorMapper.map(Object()), isA<UnknownFailure>());
    });
  });

  // T-M2.3: every named error a v2.0 household-membership RPC (spec §6.9.2)
  // can raise. Each reaches the client as a bare `raise exception '<code>'`
  // — SQLSTATE P0001, `message` set to exactly the code string — so that's
  // exactly how each is constructed here, one per code.
  group('ErrorMapper.map — v2.0 household RPC error codes (T-M2.3)', () {
    PostgrestException named(String code) =>
        PostgrestException(message: code, code: 'P0001');

    test('already_in_household', () {
      final mapped = ErrorMapper.map(named('already_in_household'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        "You're already in a household. Leave it first from Settings.",
      );
    });

    test('invalid_invite', () {
      final mapped = ErrorMapper.map(named('invalid_invite'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        "That code isn't valid any more. Ask for a fresh one.",
      );
    });

    test('household_inactive', () {
      final mapped = ErrorMapper.map(named('household_inactive'));
      expect(mapped, isA<ValidationFailure>());
      expect(mapped.message, 'That household is no longer active.');
    });

    test('last_admin', () {
      final mapped = ErrorMapper.map(named('last_admin'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        "You're the only admin. Make someone else an admin first.",
      );
    });

    test('promote_someone_first', () {
      final mapped = ErrorMapper.map(named('promote_someone_first'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        "You're the only admin. Make someone else an admin, or remove the "
        'other members first.',
      );
    });

    test('not_admin maps to PermissionFailure, not ValidationFailure', () {
      final mapped = ErrorMapper.map(named('not_admin'));
      expect(mapped, isA<PermissionFailure>());
      expect(mapped.message, 'Only an admin can do that.');
    });

    test('not_a_member', () {
      final mapped = ErrorMapper.map(named('not_a_member'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        'That person is no longer a member of this household.',
      );
    });

    test('not_in_household', () {
      final mapped = ErrorMapper.map(named('not_in_household'));
      expect(mapped, isA<ValidationFailure>());
      expect(mapped.message, 'You need to be in a household to do that.');
    });

    test('cannot_deactivate_self', () {
      final mapped = ErrorMapper.map(named('cannot_deactivate_self'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        "You can't deactivate your own account from here.",
      );
    });

    test('use_leave_household', () {
      final mapped = ErrorMapper.map(named('use_leave_household'));
      expect(mapped, isA<ValidationFailure>());
      expect(mapped.message, 'Use "Leave household" to remove yourself.');
    });

    test('household_not_empty', () {
      final mapped = ErrorMapper.map(named('household_not_empty'));
      expect(mapped, isA<ValidationFailure>());
      expect(
        mapped.message,
        "You can't delete a household while other members are still in it.",
      );
    });

    test(
      'an unrecognised P0001 message (e.g. a client bug hitting the '
      'guard_profile_membership trigger) still falls back to UnknownFailure',
      () {
        expect(
          ErrorMapper.map(named('household_id_immutable')),
          isA<UnknownFailure>(),
        );
      },
    );
  });
}
