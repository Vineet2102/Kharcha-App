import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/result/result.dart';

void main() {
  group('Result.ok', () {
    const result = Result<int, String>.ok(42);

    test('isOk/isErr', () {
      expect(result.isOk, isTrue);
      expect(result.isErr, isFalse);
    });

    test('valueOrNull/failureOrNull', () {
      expect(result.valueOrNull, 42);
      expect(result.failureOrNull, isNull);
    });

    test('fold calls onOk', () {
      expect(result.fold((v) => 'ok:$v', (f) => 'err:$f'), 'ok:42');
    });

    test('map transforms the value', () {
      final mapped = result.map((v) => v * 2);
      expect(mapped.valueOrNull, 84);
    });
  });

  group('Result.err', () {
    const result = Result<int, String>.err('boom');

    test('isOk/isErr', () {
      expect(result.isOk, isFalse);
      expect(result.isErr, isTrue);
    });

    test('valueOrNull/failureOrNull', () {
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, 'boom');
    });

    test('fold calls onErr', () {
      expect(result.fold((v) => 'ok:$v', (f) => 'err:$f'), 'err:boom');
    });

    test(
      'map passes the failure through unchanged, never calling transform',
      () {
        var called = false;
        final mapped = result.map((v) {
          called = true;
          return v * 2;
        });
        expect(mapped.failureOrNull, 'boom');
        expect(called, isFalse);
      },
    );
  });
}
