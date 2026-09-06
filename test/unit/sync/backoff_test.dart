import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/data/sync/backoff.dart';

void main() {
  group('computeBackoff', () {
    test('grows exponentially with attempts, before jitter', () {
      // A fixed Random (nextDouble always 0.5) removes jitter entirely
      // (1 + 0.5*0.4 - 0.2 == 1.0), isolating the base 2^attempts curve.
      final noJitter = _FixedRandom(0.5);
      expect(computeBackoff(1, random: noJitter), const Duration(seconds: 2));
      expect(computeBackoff(2, random: noJitter), const Duration(seconds: 4));
      expect(computeBackoff(3, random: noJitter), const Duration(seconds: 8));
    });

    test('caps at 15 minutes for large attempt counts', () {
      final noJitter = _FixedRandom(0.5);
      expect(computeBackoff(20, random: noJitter), const Duration(minutes: 15));
      expect(
        computeBackoff(1000, random: noJitter),
        const Duration(minutes: 15),
      );
    });

    test('jitter stays within ±20% of the base value', () {
      final random = Random(42);
      for (var i = 0; i < 200; i++) {
        final result = computeBackoff(4, random: random); // base = 16s
        expect(
          result.inMilliseconds,
          inInclusiveRange(16000 - 3200 - 1, 16000 + 3200 + 1),
        );
      }
    });

    test('never returns a negative duration', () {
      final result = computeBackoff(1, random: _FixedRandom(0.0));
      expect(result.isNegative, isFalse);
    });

    test('defaults to a real Random when none is injected', () {
      final result = computeBackoff(1);
      expect(result.inSeconds, inInclusiveRange(1, 3));
    });
  });
}

/// A [Random] that always returns the same [nextDouble] value, for
/// deterministic assertions on the base backoff curve.
class _FixedRandom implements Random {
  _FixedRandom(this._value);
  final double _value;

  @override
  double nextDouble() => _value;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
