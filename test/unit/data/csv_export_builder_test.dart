import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/data/export/csv_export_builder.dart';
import 'package:kharcha/domain/models/category.dart';
import 'package:kharcha/domain/models/expense.dart';
import 'package:kharcha/domain/models/income.dart';
import 'package:kharcha/domain/models/payment_method.dart';
import 'package:kharcha/domain/models/profile.dart';

void main() {
  final now = DateTime.utc(2026, 9, 3, 19, 42);

  Category category({String id = 'c1', String name = 'Groceries'}) => Category(
    id: id,
    householdId: 'h1',
    name: name,
    createdAt: now,
    updatedAt: now,
  );
  PaymentMethod method() => PaymentMethod(
    id: 'pm1',
    householdId: 'h1',
    name: 'UPI',
    createdAt: now,
    updatedAt: now,
  );
  Profile profile() => Profile(
    id: 'u1',
    householdId: 'h1',
    displayName: 'Vineet',
    createdAt: now,
    updatedAt: now,
  );

  group('buildExpenseCsv', () {
    test('starts with a UTF-8 BOM and the exact spec §11.11 header', () {
      final bytes = buildExpenseCsv(
        const [],
        categoriesById: const {},
        methodsById: const {},
        profilesById: const {},
      );

      expect(bytes.take(3).toList(), [0xEF, 0xBB, 0xBF]);
      final text = utf8.decode(bytes.skip(3).toList());
      expect(
        text.trimRight(),
        'date,time,member,amount_inr,category,payment_method,merchant,note,has_receipt,id',
      );
    });

    test('formats one row with a plain (non-grouped) decimal amount', () {
      // 19:42 IST = 14:12 UTC — the CSV's `time` column is IST wall-clock,
      // same convention as every other displayed time in this app.
      final spentAt = DateTime.utc(2026, 9, 3, 14, 12);
      final expense = Expense(
        id: '7f3c',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 45000,
        categoryId: 'c1',
        paymentMethodId: 'pm1',
        spentAt: spentAt,
        spentOn: DateTime.utc(2026, 9, 3),
        merchant: 'Reliance Fresh',
        note: 'weekly veg',
        createdAt: now,
        updatedAt: now,
      );

      final bytes = buildExpenseCsv(
        [expense],
        categoriesById: {'c1': category()},
        methodsById: {'pm1': method()},
        profilesById: {'u1': profile()},
      );
      final lines = utf8.decode(bytes.skip(3).toList()).trim().split('\r\n');

      expect(
        lines[1],
        '2026-09-03,19:42,Vineet,450.00,Groceries,UPI,Reliance Fresh,weekly veg,false,7f3c',
      );
    });

    test('an amount over 999 has no thousands separator', () {
      final expense = Expense(
        id: 'e1',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 12345600,
        spentAt: now,
        spentOn: DateTime.utc(2026, 9, 3),
        createdAt: now,
        updatedAt: now,
      );

      final bytes = buildExpenseCsv(
        [expense],
        categoriesById: const {},
        methodsById: const {},
        profilesById: const {},
      );
      final lines = utf8.decode(bytes.skip(3).toList()).trim().split('\r\n');

      // Money.format()'s Indian grouping would render '1,23,456.00' — a
      // comma inside a numeric CSV cell defeats spreadsheet SUM(), so this
      // column must stay a plain decimal.
      expect(lines[1].split(',')[3], '123456.00');
    });

    test('an unresolvable category/payment-method id falls back to blank', () {
      final expense = Expense(
        id: 'e1',
        householdId: 'h1',
        userId: 'missing-user',
        amountPaise: 100,
        categoryId: 'missing-category',
        spentAt: now,
        spentOn: DateTime.utc(2026, 9, 3),
        createdAt: now,
        updatedAt: now,
      );

      final bytes = buildExpenseCsv(
        [expense],
        categoriesById: const {},
        methodsById: const {},
        profilesById: const {},
      );
      final fields = utf8.decode(bytes.skip(3).toList()).trim().split('\r\n')[1].split(',');

      expect(fields[2], 'Unknown'); // member
      expect(fields[4], ''); // category
      expect(fields[5], ''); // payment_method
    });
  });

  group('buildIncomeCsv', () {
    test('has its own header with no time/payment_method/merchant/has_receipt', () {
      final bytes = buildIncomeCsv(
        const [],
        categoriesById: const {},
        profilesById: const {},
      );
      final text = utf8.decode(bytes.skip(3).toList());
      expect(text.trimRight(), 'date,member,amount_inr,category,source,note,id');
    });

    test('formats one row', () {
      final income = Income(
        id: 'i1',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 5000000,
        categoryId: 'c1',
        receivedAt: now,
        receivedOn: DateTime.utc(2026, 9, 3),
        source: 'Employer',
        note: 'Sept salary',
        createdAt: now,
        updatedAt: now,
      );

      final bytes = buildIncomeCsv(
        [income],
        categoriesById: {'c1': category(name: 'Salary')},
        profilesById: {'u1': profile()},
      );
      final lines = utf8.decode(bytes.skip(3).toList()).trim().split('\r\n');

      expect(lines[1], '2026-09-03,Vineet,50000.00,Salary,Employer,Sept salary,i1');
    });
  });
}
