import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/category.dart' as domain;
import '../../domain/models/expense.dart' as domain;
import '../../domain/models/expense_filter.dart';
import '../../domain/models/payment_method.dart' as domain;
import '../../domain/models/profile.dart' as domain;
import '../export/csv_export_builder.dart';
import '../export/pdf_report_builder.dart';
import '../local/mappers/attachment_mapper.dart';
import '../local/mappers/budget_mapper.dart';
import '../local/mappers/category_mapper.dart';
import '../local/mappers/expense_mapper.dart';
import '../local/mappers/household_mapper.dart';
import '../local/mappers/income_mapper.dart';
import '../local/mappers/payment_method_mapper.dart';
import '../local/mappers/profile_mapper.dart';
import '../local/mappers/recurring_rule_mapper.dart';

part 'export_repository.g.dart';

/// A wide-open `[start, end)` bound standing in for "no date filter at all"
/// against `ReportDao`'s half-open-range queries (spec §11.11's "All time"
/// preset) — simpler than adding a second, nullable-bounds code path to
/// every aggregate query this repository calls.
final _epochFloor = DateTime.utc(2000);
final _epochCeiling = DateTime.utc(2100);

/// CSV/PDF/full-backup export (spec §11.11, Phase 12). Purely a *reader* —
/// every file it produces comes from the local Drift cache (already
/// synced), and nothing here writes to the outbox or touches Supabase, same
/// as [ReportRepository].
class ExportRepository {
  ExportRepository(this._db);

  final AppDatabase _db;

  Future<Result<File, Failure>> exportExpensesCsv({
    required String householdId,
    DateTime? startDate,
    DateTime? endDate,
    List<String> memberIds = const [],
    List<String> categoryIds = const [],
  }) async {
    try {
      final rows = await _db.expenseDao.getFiltered(
        householdId: householdId,
        filter: ExpenseFilter(
          startDate: startDate,
          endDate: endDate,
          memberIds: memberIds,
          categoryIds: categoryIds,
        ),
      );
      final lookups = await _lookups(householdId);
      final bytes = buildExpenseCsv(
        rows.map((r) => r.toDomain()).toList(),
        categoriesById: lookups.categories,
        methodsById: lookups.methods,
        profilesById: lookups.profiles,
      );
      final file = await _writeTemp(
        'kharcha_${_periodToken(startDate, endDate)}_expenses.csv',
        bytes,
      );
      return Result.ok(file);
    } catch (e) {
      return Result.err(ErrorMapper.map(e));
    }
  }

  Future<Result<File, Failure>> exportIncomeCsv({
    required String householdId,
    DateTime? startDate,
    DateTime? endDate,
    List<String> memberIds = const [],
    List<String> categoryIds = const [],
  }) async {
    try {
      final rows = await _db.incomeDao.getFiltered(
        householdId: householdId,
        startDate: startDate,
        endDate: endDate,
        memberIds: memberIds,
        categoryIds: categoryIds,
      );
      final lookups = await _lookups(householdId);
      final bytes = buildIncomeCsv(
        rows.map((r) => r.toDomain()).toList(),
        categoriesById: lookups.categories,
        profilesById: lookups.profiles,
      );
      final file = await _writeTemp(
        'kharcha_${_periodToken(startDate, endDate)}_income.csv',
        bytes,
      );
      return Result.ok(file);
    } catch (e) {
      return Result.err(ErrorMapper.map(e));
    }
  }

  /// [transactionAppendix]: when true, every matching expense (same scope as
  /// [exportExpensesCsv]) is listed in full at the end of the report (spec
  /// §11.11's "Optional appendix").
  Future<Result<File, Failure>> exportPdfReport({
    required String householdId,
    DateTime? startDate,
    DateTime? endDate,
    List<String> memberIds = const [],
    List<String> categoryIds = const [],
    bool transactionAppendix = false,
  }) async {
    try {
      final household = await _db.householdDao.findById(householdId);
      final rangeStart = startDate ?? _epochFloor;
      // ReportDao's bound is half-open `[start, end)`; the UI's `endDate` is
      // an inclusive calendar date, so the query bound is one day past it.
      final rangeEnd = endDate == null
          ? _epochCeiling
          : endDate.add(const Duration(days: 1));

      final totalExpensePaise = await _db.reportDao
          .watchExpenseTotal(
            householdId: householdId,
            start: rangeStart,
            end: rangeEnd,
          )
          .first;
      final totalIncomePaise = await _db.reportDao
          .watchIncomeTotal(
            householdId: householdId,
            start: rangeStart,
            end: rangeEnd,
          )
          .first;
      final categoryTotals = await _db.reportDao
          .watchExpenseByCategory(
            householdId: householdId,
            start: rangeStart,
            end: rangeEnd,
          )
          .first;
      final memberTotals = await _db.reportDao
          .watchExpenseByMember(
            householdId: householdId,
            start: rangeStart,
            end: rangeEnd,
          )
          .first;

      final lookups = await _lookups(householdId);
      final categoryRows = [
        for (final t in categoryTotals)
          PdfBreakdownRow(
            label: lookups.categories[t.key]?.name ?? 'Uncategorised',
            amountPaise: t.amountPaise,
            pct: totalExpensePaise == 0
                ? 0
                : t.amountPaise / totalExpensePaise * 100,
          ),
      ];
      final memberRows = [
        for (final t in memberTotals)
          PdfBreakdownRow(
            label: lookups.profiles[t.key]?.displayName ?? 'Unknown',
            amountPaise: t.amountPaise,
            pct: totalExpensePaise == 0
                ? 0
                : t.amountPaise / totalExpensePaise * 100,
          ),
      ];

      var transactionRows = const <PdfTransactionRow>[];
      if (transactionAppendix) {
        final expenses = await _db.expenseDao.getFiltered(
          householdId: householdId,
          filter: ExpenseFilter(
            startDate: startDate,
            endDate: endDate,
            memberIds: memberIds,
            categoryIds: categoryIds,
          ),
        );
        transactionRows = [
          for (final row in expenses) _transactionRow(row.toDomain(), lookups),
        ];
      }

      final fonts = await _loadReportFonts();
      final bytes = await buildReportPdf(
        regularFont: fonts.$1,
        boldFont: fonts.$2,
        householdName: household?.name ?? 'Kharcha',
        periodLabel: _periodLabel(startDate, endDate),
        generatedAt: DateTime.now().toUtc(),
        totalExpensePaise: totalExpensePaise,
        totalIncomePaise: totalIncomePaise,
        categoryRows: categoryRows,
        memberRows: memberRows,
        transactions: transactionRows,
      );
      final file = await _writeTemp(
        'kharcha_${_periodToken(startDate, endDate)}_report.pdf',
        bytes,
      );
      return Result.ok(file);
    } catch (e) {
      return Result.err(ErrorMapper.map(e));
    }
  }

  /// Admin-only disaster-recovery escape hatch (spec §11.11): every row of
  /// every table for the household, as one JSON file — including
  /// soft-deleted rows, unlike every other read in this app, since a backup
  /// is meant to be a full-fidelity snapshot, not a live view.
  Future<Result<File, Failure>> exportFullBackupJson({
    required String householdId,
  }) async {
    try {
      final households = await _db.select(_db.households).get();
      final profiles = await _db.select(_db.profiles).get();
      final categories = await _db.select(_db.categories).get();
      final paymentMethods = await _db.select(_db.paymentMethods).get();
      final expenses = await _db.select(_db.expenses).get();
      final incomes = await _db.select(_db.incomes).get();
      final attachments = await _db.select(_db.attachments).get();
      final budgets = await _db.select(_db.budgets).get();
      final recurringRules = await _db.select(_db.recurringRules).get();

      final backup = <String, Object?>{
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'household_id': householdId,
        'households': [for (final r in households) r.toDomain().toJson()],
        'profiles': [for (final r in profiles) r.toDomain().toJson()],
        'categories': [for (final r in categories) r.toDomain().toJson()],
        'payment_methods': [
          for (final r in paymentMethods) r.toDomain().toJson(),
        ],
        'expenses': [for (final r in expenses) r.toDomain().toJson()],
        'incomes': [for (final r in incomes) r.toDomain().toJson()],
        'attachments': [for (final r in attachments) r.toDomain().toJson()],
        'budgets': [for (final r in budgets) r.toDomain().toJson()],
        'recurring_rules': [
          for (final r in recurringRules) r.toDomain().toJson(),
        ],
      };
      final bytes = Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(backup)),
      );
      final file = await _writeTemp(
        'kharcha_${_todayToken()}_backup.json',
        bytes,
      );
      return Result.ok(file);
    } catch (e) {
      return Result.err(ErrorMapper.map(e));
    }
  }

  PdfTransactionRow _transactionRow(domain.Expense expense, _Lookups lookups) =>
      PdfTransactionRow(
        date: _dateToken(expense.spentOn),
        time: _timeToken(expense.spentAt),
        member: lookups.profiles[expense.userId]?.displayName ?? 'Unknown',
        amountPaise: expense.amountPaise,
        category: lookups.categories[expense.categoryId]?.name ?? '',
        paymentMethod: lookups.methods[expense.paymentMethodId]?.name ?? '',
        merchant: expense.merchant,
        note: expense.note,
      );

  Future<_Lookups> _lookups(String householdId) async {
    final categories = await _db.categoryDao.watchAll(householdId).first;
    final methods = await _db.paymentMethodDao.watchAll(householdId).first;
    final profiles = await _db.profileDao.watchAll(householdId).first;
    return _Lookups(
      categories: {for (final c in categories) c.id: c.toDomain()},
      methods: {for (final m in methods) m.id: m.toDomain()},
      profiles: {for (final p in profiles) p.id: p.toDomain()},
    );
  }

  Future<(pw.Font, pw.Font)> _loadReportFonts() async {
    final regularData = await rootBundle.load(
      'assets/fonts/NotoSans-Regular.ttf',
    );
    final boldData = await rootBundle.load('assets/fonts/NotoSans-Bold.ttf');
    return (pw.Font.ttf(regularData), pw.Font.ttf(boldData));
  }

  Future<File> _writeTemp(String filename, Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, filename));
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _periodLabel(DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return 'All time';
    if (startDate != null &&
        endDate != null &&
        startDate.isAtSameMomentAs(AppTime.monthStart(startDate)) &&
        endDate.isAtSameMomentAs(
          AppTime.monthAfter(startDate, 1).subtract(const Duration(days: 1)),
        )) {
      return AppTime.monthLabel(startDate);
    }
    return '${_dateToken(startDate!)} – ${_dateToken(endDate!)}';
  }

  String _periodToken(DateTime? startDate, DateTime? endDate) {
    if (startDate == null && endDate == null) return 'all';
    if (startDate != null &&
        endDate != null &&
        startDate.isAtSameMomentAs(AppTime.monthStart(startDate)) &&
        endDate.isAtSameMomentAs(
          AppTime.monthAfter(startDate, 1).subtract(const Duration(days: 1)),
        )) {
      return '${startDate.year.toString().padLeft(4, '0')}-'
          '${startDate.month.toString().padLeft(2, '0')}';
    }
    return '${_dateToken(startDate!)}_to_${_dateToken(endDate!)}';
  }

  String _todayToken() =>
      _dateToken(AppTime.calendarDate(DateTime.now().toUtc()));

  String _dateToken(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  String _timeToken(DateTime instant) {
    final ist = AppTime.toIst(instant);
    return '${ist.hour.toString().padLeft(2, '0')}:'
        '${ist.minute.toString().padLeft(2, '0')}';
  }
}

class _Lookups {
  const _Lookups({
    required this.categories,
    required this.methods,
    required this.profiles,
  });

  final Map<String, domain.Category> categories;
  final Map<String, domain.PaymentMethod> methods;
  final Map<String, domain.Profile> profiles;
}

@Riverpod(keepAlive: true)
ExportRepository exportRepository(Ref ref) =>
    ExportRepository(ref.watch(appDatabaseProvider));
