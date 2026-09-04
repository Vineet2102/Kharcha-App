import 'package:intl/intl.dart';

/// All monetary values in this app are integer paise (₹1 = 100 paise).
/// Never use `double`/`num` for a stored amount — only for parsing user
/// input and formatting for display (spec §9.4, §6.1).
extension type const Money(int paise) {
  static Money fromRupees(num rupees) => Money((rupees * 100).round());

  static const zero = Money(0);

  double get rupees => paise / 100.0;

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  bool operator <(Money other) => paise < other.paise;
  bool operator <=(Money other) => paise <= other.paise;
  bool operator >(Money other) => paise > other.paise;
  bool operator >=(Money other) => paise >= other.paise;

  bool get isPositive => paise > 0;
  bool get isNegative => paise < 0;

  static final NumberFormat _symbolFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );
  static final NumberFormat _plainFormat = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '',
    decimalDigits: 2,
  );

  /// '₹1,23,456.78' (Indian digit grouping), or '₹1.2L' / '₹3.4Cr' when
  /// [compact] is true — used for chart axis labels.
  String format({bool withSymbol = true, bool compact = false}) {
    if (compact) return _formatCompact(withSymbol: withSymbol);
    final formatter = withSymbol ? _symbolFormat : _plainFormat;
    return formatter.format(rupees).trim();
  }

  String _formatCompact({required bool withSymbol}) {
    final symbol = withSymbol ? '₹' : '';
    final sign = rupees < 0 ? '-' : '';
    final abs = rupees.abs();
    if (abs >= 10000000) return '$sign$symbol${_trim(abs / 10000000)}Cr';
    if (abs >= 100000) return '$sign$symbol${_trim(abs / 100000)}L';
    if (abs >= 1000) return '$sign$symbol${_trim(abs / 1000)}k';
    return '$sign$symbol${abs.toStringAsFixed(0)}';
  }

  static String _trim(double value) {
    final rounded = (value * 10).round() / 10;
    return rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : rounded.toStringAsFixed(1);
  }

  /// Parses `1234`, `1234.5`, `1,234.50`, `1234.567` (rounded to 2dp).
  /// Rejects negative and zero amounts. Returns null when invalid.
  static Money? tryParse(String input) {
    final cleaned = input.trim().replaceAll(',', '');
    if (cleaned.isEmpty) return null;
    final value = num.tryParse(cleaned);
    if (value == null || value <= 0) return null;
    return fromRupees(value);
  }
}
