import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../core/time/app_time.dart';
import '../../domain/models/category.dart' as domain;
import '../../domain/models/expense.dart' as domain;
import '../../domain/models/income.dart' as domain;
import '../../domain/models/payment_method.dart' as domain;
import '../../domain/models/profile.dart' as domain;

/// Pure CSV builders for the Export screen (spec §11.11, T-12.1). Every
/// output is UTF-8 **with a BOM** (`﻿`) so Excel on Windows opens it
/// with the ₹ symbol intact instead of guessing the wrong codepage — a
/// plain UTF-8 file (no BOM) is the one thing spec §11.11 calls out
/// specifically, and Excel gets it wrong by default.
///
/// `amount_inr` is a plain decimal (`450.00`), never `Money.format()`'s
/// Indian-grouped `1,23,456.00` — a comma inside a numeric CSV column
/// forces the field to be quoted and stops a spreadsheet from summing it
/// as a number directly, which defeats the point of a CSV export.
const _expenseHeader = [
  'date',
  'time',
  'member',
  'amount_inr',
  'category',
  'payment_method',
  'merchant',
  'note',
  'has_receipt',
  'id',
];

/// No `time`/`payment_method`/`merchant`/`has_receipt` columns — the
/// `incomes` table has none of those (spec §11.6: income is date-only, has
/// no payment method).
const _incomeHeader = [
  'date',
  'member',
  'amount_inr',
  'category',
  'source',
  'note',
  'id',
];

Uint8List buildExpenseCsv(
  List<domain.Expense> expenses, {
  required Map<String, domain.Category> categoriesById,
  required Map<String, domain.PaymentMethod> methodsById,
  required Map<String, domain.Profile> profilesById,
}) {
  final rows = <List<String>>[
    _expenseHeader,
    for (final e in expenses)
      [
        _dateStr(e.spentOn),
        _timeStr(e.spentAt),
        profilesById[e.userId]?.displayName ?? 'Unknown',
        _amountStr(e.amountPaise),
        categoriesById[e.categoryId]?.name ?? '',
        methodsById[e.paymentMethodId]?.name ?? '',
        e.merchant,
        e.note,
        e.hasReceipt.toString(),
        e.id,
      ],
  ];
  return _toCsvBytes(rows);
}

Uint8List buildIncomeCsv(
  List<domain.Income> incomes, {
  required Map<String, domain.Category> categoriesById,
  required Map<String, domain.Profile> profilesById,
}) {
  final rows = <List<String>>[
    _incomeHeader,
    for (final i in incomes)
      [
        _dateStr(i.receivedOn),
        profilesById[i.userId]?.displayName ?? 'Unknown',
        _amountStr(i.amountPaise),
        categoriesById[i.categoryId]?.name ?? '',
        i.source,
        i.note,
        i.id,
      ],
  ];
  return _toCsvBytes(rows);
}

String _dateStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// [instant] is a UTC timestamp; the displayed time-of-day is IST, same
/// convention as every other user-facing time in this app.
String _timeStr(DateTime instant) {
  final ist = AppTime.toIst(instant);
  return '${ist.hour.toString().padLeft(2, '0')}:'
      '${ist.minute.toString().padLeft(2, '0')}';
}

String _amountStr(int paise) => (paise / 100).toStringAsFixed(2);

/// `addBom: true` is the `csv` package's own UTF-8-BOM support — no need to
/// prepend the 3 BOM bytes by hand.
const _encoder = CsvEncoder(addBom: true);

Uint8List _toCsvBytes(List<List<String>> rows) =>
    Uint8List.fromList(utf8.encode(_encoder.convert(rows)));
