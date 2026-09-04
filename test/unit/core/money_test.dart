import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/money/money.dart';

void main() {
  group('Money.fromRupees', () {
    test('converts rupees to paise', () {
      expect(Money.fromRupees(1234.56).paise, 123456);
    });

    test('rounds to the nearest paisa', () {
      expect(Money.fromRupees(99.995).paise, 10000);
    });
  });

  group('Money.tryParse', () {
    test('parses plain integers', () {
      expect(Money.tryParse('1234')?.paise, 123400);
    });

    test('parses decimals', () {
      expect(Money.tryParse('1234.5')?.paise, 123450);
    });

    test('parses comma-grouped input', () {
      expect(Money.tryParse('1,234.50')?.paise, 123450);
    });

    test('rounds a third-decimal-place input to 2dp', () {
      expect(Money.tryParse('1234.567')?.paise, 123457);
    });

    test('rejects zero', () {
      expect(Money.tryParse('0'), isNull);
    });

    test('rejects negative amounts', () {
      expect(Money.tryParse('-5'), isNull);
    });

    test('rejects non-numeric input', () {
      expect(Money.tryParse('abc'), isNull);
    });

    test('rejects empty input', () {
      expect(Money.tryParse(''), isNull);
    });
  });

  group('Money.format', () {
    test('applies Indian digit grouping', () {
      expect(Money.fromRupees(123456.78).format(), contains('1,23,456.78'));
    });

    test('formats one lakh compactly', () {
      expect(Money.fromRupees(100000).format(compact: true), '₹1L');
    });

    test('formats one crore compactly', () {
      expect(Money.fromRupees(10000000).format(compact: true), '₹1Cr');
    });

    test('formats sub-lakh amounts compactly in thousands', () {
      expect(Money.fromRupees(2500).format(compact: true), '₹2.5k');
    });
  });

  group('Money arithmetic', () {
    test('add and subtract', () {
      final a = Money.fromRupees(100);
      final b = Money.fromRupees(30);
      expect((a + b).paise, Money.fromRupees(130).paise);
      expect((a - b).paise, Money.fromRupees(70).paise);
    });

    test('net savings can be negative', () {
      final income = Money.fromRupees(100);
      final expense = Money.fromRupees(150);
      final net = income - expense;
      expect(net.isNegative, isTrue);
    });
  });
}
