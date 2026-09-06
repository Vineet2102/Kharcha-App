import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/data/export/pdf_report_builder.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  // Base14 Helvetica stands in for the real bundled NotoSans pair (which
  // needs `rootBundle`/an asset bundle, unavailable to a plain unit test) —
  // this file is only exercising the document layout, not glyph coverage.
  final regular = pw.Font.helvetica();
  final bold = pw.Font.helveticaBold();

  test('produces a non-empty PDF with no category/member data', () async {
    final bytes = await buildReportPdf(
      regularFont: regular,
      boldFont: bold,
      householdName: 'Panicker Family',
      periodLabel: 'September 2026',
      generatedAt: DateTime.utc(2026, 9, 6, 10, 0),
      totalExpensePaise: 0,
      totalIncomePaise: 0,
      categoryRows: const [],
      memberRows: const [],
    );

    expect(bytes, isNotEmpty);
    // A PDF file always starts with this magic header.
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  test('produces a larger PDF when the transaction appendix is included', () async {
    final withoutAppendix = await buildReportPdf(
      regularFont: regular,
      boldFont: bold,
      householdName: 'Panicker Family',
      periodLabel: 'September 2026',
      generatedAt: DateTime.utc(2026, 9, 6, 10, 0),
      totalExpensePaise: 45000,
      totalIncomePaise: 5000000,
      categoryRows: const [
        PdfBreakdownRow(label: 'Groceries', amountPaise: 45000, pct: 100),
      ],
      memberRows: const [
        PdfBreakdownRow(label: 'Vineet', amountPaise: 45000, pct: 100),
      ],
    );

    final withAppendix = await buildReportPdf(
      regularFont: regular,
      boldFont: bold,
      householdName: 'Panicker Family',
      periodLabel: 'September 2026',
      generatedAt: DateTime.utc(2026, 9, 6, 10, 0),
      totalExpensePaise: 45000,
      totalIncomePaise: 5000000,
      categoryRows: const [
        PdfBreakdownRow(label: 'Groceries', amountPaise: 45000, pct: 100),
      ],
      memberRows: const [
        PdfBreakdownRow(label: 'Vineet', amountPaise: 45000, pct: 100),
      ],
      transactions: const [
        PdfTransactionRow(
          date: '2026-09-03',
          time: '19:42',
          member: 'Vineet',
          amountPaise: 45000,
          category: 'Groceries',
          paymentMethod: 'UPI',
          merchant: 'Reliance Fresh',
          note: 'weekly veg',
        ),
      ],
    );

    expect(withAppendix.length, greaterThan(withoutAppendix.length));
  });
}
