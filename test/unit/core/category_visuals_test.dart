import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/constants/category_visuals.dart';
import 'package:kharcha/domain/models/enums.dart';

void main() {
  group('colourFromHex', () {
    test('parses a #RRGGBB hex string to an opaque Color', () {
      expect(colourFromHex('#607D8B'), const Color(0xFF607D8B));
    });

    test('works without the leading #', () {
      expect(colourFromHex('607D8B'), const Color(0xFF607D8B));
    });
  });

  group('iconForKey', () {
    test('resolves a known key', () {
      expect(iconForKey('restaurant'), Icons.restaurant);
    });

    test('falls back to the generic category icon for an unknown key', () {
      expect(iconForKey('not_a_real_key'), Icons.category);
    });
  });

  group('iconForPaymentMethodType', () {
    test('every PayMethodType value maps to a distinct icon', () {
      final icons = PayMethodType.values.map(iconForPaymentMethodType).toSet();
      expect(icons, hasLength(PayMethodType.values.length));
    });

    test('cash maps to the payments icon', () {
      expect(
        iconForPaymentMethodType(PayMethodType.cash),
        Icons.payments_outlined,
      );
    });
  });

  test('categoryColourPalette has exactly 16 swatches, all valid hex', () {
    expect(categoryColourPalette, hasLength(16));
    for (final hex in categoryColourPalette) {
      expect(() => colourFromHex(hex), returnsNormally);
    }
  });
}
