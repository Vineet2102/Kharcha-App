import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/money/money.dart';

/// One row of the "spend by category"/"spend by member" tables (spec
/// §11.11): a pre-resolved display name (never a raw id — this builder has
/// no DB access, by design, so it stays testable without Drift) paired with
/// its share of the period's total expense spend.
class PdfBreakdownRow {
  const PdfBreakdownRow({
    required this.label,
    required this.amountPaise,
    required this.pct,
  });

  final String label;
  final int amountPaise;
  final double pct;
}

/// One row of the optional full-transaction-list appendix — same shape as
/// the expense CSV row (`buildExpenseCsv`), pre-resolved to display strings
/// for the same reason as [PdfBreakdownRow].
class PdfTransactionRow {
  const PdfTransactionRow({
    required this.date,
    required this.time,
    required this.member,
    required this.amountPaise,
    required this.category,
    required this.paymentMethod,
    required this.merchant,
    required this.note,
  });

  final String date;
  final String time;
  final String member;
  final int amountPaise;
  final String category;
  final String paymentMethod;
  final String merchant;
  final String note;
}

/// Builds the Export PDF report (spec §11.11, T-12.2): title/household/
/// period/generation timestamp, a summary block, category and member
/// breakdown tables, and an optional full-transaction-list appendix. No
/// images/receipts are embedded, per spec, to keep the file small.
///
/// [regularFont]/[boldFont] are injected (rather than loaded here via
/// `rootBundle`) so this stays a plain, Flutter-binding-free function that
/// can be unit tested with `pw.Font.helvetica()`/`pw.Font.helveticaBold()` —
/// the real caller loads the bundled NotoSans pair (see
/// `ExportRepository._loadReportFonts`), which is what actually renders the
/// ₹ glyph; base14 Helvetica silently has no glyph for it.
Future<Uint8List> buildReportPdf({
  required pw.Font regularFont,
  required pw.Font boldFont,
  required String householdName,
  required String periodLabel,
  required DateTime generatedAt,
  required int totalExpensePaise,
  required int totalIncomePaise,
  required List<PdfBreakdownRow> categoryRows,
  required List<PdfBreakdownRow> memberRows,
  List<PdfTransactionRow> transactions = const [],
}) async {
  final doc = pw.Document(
    theme: pw.ThemeData.withFont(base: regularFont, bold: boldFont),
  );
  final netPaise = totalIncomePaise - totalExpensePaise;

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text('Kharcha Report', style: const pw.TextStyle(fontSize: 22)),
        pw.SizedBox(height: 4),
        pw.Text(householdName, style: const pw.TextStyle(fontSize: 13)),
        pw.Text(
          periodLabel,
          style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700),
        ),
        pw.Text(
          'Generated ${_fmtDateTime(generatedAt)}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        pw.SizedBox(height: 20),
        _summaryBlock(totalExpensePaise, totalIncomePaise, netPaise),
        pw.SizedBox(height: 20),
        _sectionHeading('Spend by category'),
        _breakdownTable(categoryRows, 'Category'),
        pw.SizedBox(height: 20),
        _sectionHeading('Spend by member'),
        _breakdownTable(memberRows, 'Member'),
        if (transactions.isNotEmpty) ...[
          pw.SizedBox(height: 20),
          _sectionHeading('Transactions'),
          _transactionsTable(transactions),
        ],
      ],
    ),
  );
  return doc.save();
}

pw.Widget _sectionHeading(String text) => pw.Text(
  text,
  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
);

pw.Widget _summaryBlock(int expensePaise, int incomePaise, int netPaise) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(color: PdfColors.grey400),
      borderRadius: pw.BorderRadius.circular(4),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        _summaryStat('Total expense', expensePaise),
        _summaryStat('Total income', incomePaise),
        _summaryStat('Net', netPaise),
      ],
    ),
  );
}

pw.Widget _summaryStat(String label, int paise) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Text(
      label,
      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
    ),
    pw.SizedBox(height: 2),
    pw.Text(
      Money(paise).format(),
      style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
    ),
  ],
);

pw.Widget _breakdownTable(List<PdfBreakdownRow> rows, String labelHeader) {
  if (rows.isEmpty) {
    return pw.Text(
      'No data for this period.',
      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
    );
  }
  return pw.TableHelper.fromTextArray(
    headers: [labelHeader, 'Amount', '%'],
    data: [
      for (final r in rows)
        [
          r.label,
          Money(r.amountPaise).format(),
          '${r.pct.toStringAsFixed(1)}%',
        ],
    ],
    headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 9),
    cellAlignments: const {
      1: pw.Alignment.centerRight,
      2: pw.Alignment.centerRight,
    },
    headerAlignments: const {
      1: pw.Alignment.centerRight,
      2: pw.Alignment.centerRight,
    },
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  );
}

pw.Widget _transactionsTable(List<PdfTransactionRow> rows) {
  return pw.TableHelper.fromTextArray(
    headers: [
      'Date',
      'Time',
      'Member',
      'Amount',
      'Category',
      'Payment',
      'Merchant',
      'Note',
    ],
    data: [
      for (final r in rows)
        [
          r.date,
          r.time,
          r.member,
          Money(r.amountPaise).format(),
          r.category,
          r.paymentMethod,
          r.merchant,
          r.note,
        ],
    ],
    headerStyle: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
    cellStyle: const pw.TextStyle(fontSize: 8),
    cellAlignments: const {3: pw.Alignment.centerRight},
    headerAlignments: const {3: pw.Alignment.centerRight},
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
  );
}

String _fmtDateTime(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:'
    '${d.minute.toString().padLeft(2, '0')}';
