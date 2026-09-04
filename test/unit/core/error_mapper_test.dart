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

    test('maps an unrecognised object to UnknownFailure', () {
      expect(ErrorMapper.map(Object()), isA<UnknownFailure>());
    });
  });
}
