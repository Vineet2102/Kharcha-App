import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/errors/failure.dart';
import 'package:kharcha/data/repositories/auth_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AuthRepository repository;

  setUpAll(() {
    registerFallbackValue(UserAttributes());
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
