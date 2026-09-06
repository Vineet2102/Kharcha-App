import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/errors/failure.dart';
import 'package:kharcha/data/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockSession extends Mock implements Session {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(UserAttributes());
    registerFallbackValue(OtpType.signup);
  });

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    repository = AuthRepository(client);
  });

  group('signIn', () {
    test('returns Ok on success', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenAnswer((_) async => AuthResponse());

      final result = await repository.signIn(
        email: 'a@b.com',
        password: 'secret',
      );

      expect(result.isOk, isTrue);
    });

    test(
      'maps invalid credentials to the spec-exact message (T-3.3)',
      () async {
        when(
          () => auth.signInWithPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          ),
        ).thenThrow(const AuthException('Invalid login credentials'));

        final result = await repository.signIn(
          email: 'a@b.com',
          password: 'wrong',
        );

        expect(result.failureOrNull, isA<AuthFailure>());
        expect(
          result.failureOrNull!.message,
          'Email or password is incorrect.',
        );
      },
    );

    test('maps a network error to the sign-in-specific offline message', () async {
      when(
        () => auth.signInWithPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        ),
      ).thenThrow(const SocketException('no route to host'));

      final result = await repository.signIn(
        email: 'a@b.com',
        password: 'secret',
      );

      expect(result.failureOrNull, isA<NetworkFailure>());
      expect(
        result.failureOrNull!.message,
        "You're offline. Sign in needs an internet connection the first time.",
      );
    });
  });

  group('signUp', () {
    test('returns Ok on success', () async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => AuthResponse());

      final result = await repository.signUp(
        displayName: 'Vineet',
        email: 'a@b.com',
        password: 'secret123',
      );

      expect(result.isOk, isTrue);
    });

    test('passes the display name as user metadata (T-M2.4)', () async {
      when(
        () => auth.signUp(
          email: any(named: 'email'),
          password: any(named: 'password'),
          data: any(named: 'data'),
        ),
      ).thenAnswer((_) async => AuthResponse());

      await repository.signUp(
        displayName: 'Vineet',
        email: 'a@b.com',
        password: 'secret123',
      );

      verify(
        () => auth.signUp(
          email: 'a@b.com',
          password: 'secret123',
          data: {'display_name': 'Vineet'},
        ),
      ).called(1);
    });

    test(
      'maps an already-registered email to the spec-exact message',
      () async {
        when(
          () => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          ),
        ).thenThrow(
          const AuthException(
            'A user with this email address has already been registered',
            code: 'user_already_exists',
          ),
        );

        final result = await repository.signUp(
          displayName: 'Vineet',
          email: 'a@b.com',
          password: 'secret123',
        );

        expect(result.failureOrNull, isA<AuthFailure>());
        expect(
          result.failureOrNull!.message,
          "That email already has an account — sign in instead?",
        );
      },
    );

    test(
      'maps a network error to the sign-up-specific offline message',
      () async {
        when(
          () => auth.signUp(
            email: any(named: 'email'),
            password: any(named: 'password'),
            data: any(named: 'data'),
          ),
        ).thenThrow(const SocketException('no route to host'));

        final result = await repository.signUp(
          displayName: 'Vineet',
          email: 'a@b.com',
          password: 'secret123',
        );

        expect(result.failureOrNull, isA<NetworkFailure>());
        expect(
          result.failureOrNull!.message,
          'Creating an account needs an internet connection.',
        );
      },
    );
  });

  group('resendConfirmationEmail', () {
    test('returns Ok on success and calls resend with type signup', () async {
      when(
        () => auth.resend(
          email: any(named: 'email'),
          type: any(named: 'type'),
        ),
      ).thenAnswer((_) async => ResendResponse());

      final result = await repository.resendConfirmationEmail('a@b.com');

      expect(result.isOk, isTrue);
      verify(() => auth.resend(email: 'a@b.com', type: OtpType.signup))
          .called(1);
    });

    test('maps a thrown error through ErrorMapper', () async {
      when(
        () => auth.resend(
          email: any(named: 'email'),
          type: any(named: 'type'),
        ),
      ).thenThrow(const AuthException('boom'));

      final result = await repository.resendConfirmationEmail('a@b.com');

      expect(result.isErr, isTrue);
    });
  });

  group('tryRefreshSession', () {
    test('returns true when refreshing yields a session', () async {
      when(() => auth.refreshSession()).thenAnswer((_) async => AuthResponse());
      when(() => auth.currentSession).thenReturn(MockSession());

      expect(await repository.tryRefreshSession(), isTrue);
    });

    test('returns false when there is nothing to refresh yet', () async {
      when(() => auth.refreshSession())
          .thenThrow(AuthSessionMissingException());

      expect(await repository.tryRefreshSession(), isFalse);
    });

    test('returns false on any other thrown error', () async {
      when(() => auth.refreshSession())
          .thenThrow(const SocketException('no route'));

      expect(await repository.tryRefreshSession(), isFalse);
    });
  });

  group('signOut', () {
    test('returns Ok on success', () async {
      when(() => auth.signOut()).thenAnswer((_) async {});
      final result = await repository.signOut();
      expect(result.isOk, isTrue);
    });

    test('maps a thrown error through ErrorMapper', () async {
      when(() => auth.signOut()).thenThrow(const AuthException('boom'));
      final result = await repository.signOut();
      expect(result.isErr, isTrue);
    });
  });

  group('resetPassword', () {
    test('returns Ok on success', () async {
      when(() => auth.resetPasswordForEmail(any())).thenAnswer((_) async {});
      final result = await repository.resetPassword('a@b.com');
      expect(result.isOk, isTrue);
    });
  });

  group('updatePassword', () {
    test('returns Ok on success (T-14.2)', () async {
      when(() => auth.updateUser(any()))
          .thenAnswer((_) async => UserResponse.fromJson({'id': 'u1'}));
      final result = await repository.updatePassword('newSecret123');
      expect(result.isOk, isTrue);
      verify(() => auth.updateUser(any())).called(1);
    });

    test('maps a thrown error through ErrorMapper', () async {
      when(() => auth.updateUser(any())).thenThrow(const AuthException('boom'));
      final result = await repository.updatePassword('newSecret123');
      expect(result.isErr, isTrue);
    });
  });

  test('currentSession delegates to the client', () {
    when(() => auth.currentSession).thenReturn(null);
    expect(repository.currentSession, isNull);
    verify(() => auth.currentSession).called(1);
  });
}
