import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/sync/recurring_posting_engine.dart';

// Drift decodes a stored instant with `isUtc: false` even though it was
// written as UTC (see docs/DECISIONS.md) — every raw row field read
// directly in these tests (bypassing the `.toDomain()` mappers that fix
// this in production code) must be re-flagged via `.toUtc()` before use.
const _householdId = 'h1';
const _userId = 'u1';
final _today = DateTime.utc(2026, 6, 15);

void main() {
  late AppDatabase db;
  late RecurringPostingEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    engine = RecurringPostingEngine(db);
  });

  tearDown(() => db.close());

  Future<void> insertRule({
    required String id,
    String kind = 'expense',
    required DateTime nextDueDate,
    String frequency = 'monthly',
    int intervalN = 1,
    bool autoPost = false,
    DateTime? endDate,
    DateTime? lastPostedOn,
    bool isActive = true,
  }) => db.recurringDao.upsert(
    RecurringRulesCompanion.insert(
      id: id,
      householdId: _householdId,
      userId: _userId,
      kind: Value(kind),
      title: 'Netflix',
      amountPaise: 50000,
      frequency: frequency,
      intervalN: Value(intervalN),
      startDate: DateTime.utc(2025, 1, 1),
      endDate: Value(endDate),
      nextDueDate: nextDueDate,
      autoPost: Value(autoPost),
      isActive: Value(isActive),
      lastPostedOn: Value(lastPostedOn),
      createdAt: DateTime.utc(2025, 1, 1),
      updatedAt: DateTime.utc(2025, 1, 1),
    ),
  );

  group('auto-post rules', () {
    test('posts the due occurrence and advances next_due_date', () async {
      await insertRule(
        id: 'r1',
        nextDueDate: DateTime.utc(2026, 6, 1),
        autoPost: true,
      );

      await engine.run(_householdId, asOf: _today);

      final expenses = await db.expenseDao.watchAll(_householdId).first;
      expect(expenses, hasLength(1));
      expect(expenses.single.recurringRuleId, 'r1');
      expect(expenses.single.occurrenceDate!.toUtc(), DateTime.utc(2026, 6, 1));
      expect(expenses.single.merchant, 'Netflix');
      expect(expenses.single.amountPaise, 50000);

      final rule = await db.recurringDao.findById('r1');
      expect(rule!.nextDueDate.toUtc(), DateTime.utc(2026, 7, 1));
      expect(rule.lastPostedOn!.toUtc(), DateTime.utc(2026, 6, 1));

      final outbox = await (db.select(db.outboxEntries)).get();
      final entities = outbox.map((e) => e.entity).toSet();
      expect(entities, {'expense', 'recurring_rule'});
    });

    test('creates an income row for an income-kind rule', () async {
      await insertRule(
        id: 'r1',
        kind: 'income',
        nextDueDate: DateTime.utc(2026, 6, 1),
        autoPost: true,
      );

      await engine.run(_householdId, asOf: _today);

      final incomes = await db.incomeDao.watchAll(_householdId).first;
      expect(incomes, hasLength(1));
      expect(incomes.single.source, 'Netflix');
      expect(incomes.single.recurringRuleId, 'r1');
    });

    test(
      'a rule dormant for 2 years posts at most 24 occurrences per run',
      () async {
        await insertRule(
          id: 'r1',
          nextDueDate: DateTime.utc(2024, 6, 1),
          autoPost: true,
        );

        await engine.run(_householdId, asOf: _today);

        final expenses = await db.expenseDao.watchAll(_householdId).first;
        expect(expenses, hasLength(24));

        final rule = await db.recurringDao.findById('r1');
        expect(rule!.nextDueDate.toUtc(), DateTime.utc(2026, 6, 1));

        // A second run picks up the rest.
        await engine.run(_householdId, asOf: _today);
        final expensesAfterSecondRun = await db.expenseDao
            .watchAll(_householdId)
            .first;
        expect(expensesAfterSecondRun.length, greaterThan(24));
      },
    );

    test('is idempotent if the occurrence already exists locally', () async {
      await insertRule(
        id: 'r1',
        nextDueDate: DateTime.utc(2026, 6, 1),
        autoPost: true,
      );
      // Simulate a prior partial run that created the row but crashed
      // before advancing next_due_date.
      await db.expenseDao.upsert(
        ExpensesCompanion.insert(
          id: 'already-there',
          householdId: _householdId,
          userId: _userId,
          amountPaise: 50000,
          spentAt: DateTime.utc(2026, 6, 1),
          spentOn: DateTime.utc(2026, 6, 1),
          recurringRuleId: const Value('r1'),
          occurrenceDate: Value(DateTime.utc(2026, 6, 1)),
          createdAt: DateTime.utc(2026, 6, 1),
          updatedAt: DateTime.utc(2026, 6, 1),
        ),
      );

      await engine.run(_householdId, asOf: _today);

      final expenses = await db.expenseDao.watchAll(_householdId).first;
      expect(expenses, hasLength(1)); // no duplicate created
    });

    test('deactivates the rule once it runs past its end date', () async {
      await insertRule(
        id: 'r1',
        nextDueDate: DateTime.utc(2026, 6, 1),
        endDate: DateTime.utc(2026, 6, 1),
        autoPost: true,
      );

      // asOf must reach past the *next* occurrence after the end date for
      // the engine to actually evaluate (and reject) it in this same run —
      // see the "dueOccurrencesFor" tests for the pure-function version of
      // this boundary.
      await engine.run(_householdId, asOf: DateTime.utc(2026, 7, 1));

      final rule = await db.recurringDao.findById('r1');
      expect(rule!.isActive, isFalse);
      final expenses = await db.expenseDao.watchAll(_householdId).first;
      expect(expenses, hasLength(1)); // the final, on-end-date occurrence
    });
  });

  group('manual (non-auto-post) rules', () {
    test('does not post or advance a merely-due rule', () async {
      await insertRule(id: 'r1', nextDueDate: DateTime.utc(2026, 6, 1));

      await engine.run(_householdId, asOf: _today);

      final expenses = await db.expenseDao.watchAll(_householdId).first;
      expect(expenses, isEmpty);
      final rule = await db.recurringDao.findById('r1');
      expect(rule!.nextDueDate.toUtc(), DateTime.utc(2026, 6, 1)); // untouched
    });

    test('silently skips occurrences older than 30 days, leaving the most '
        'recent still-askable one pending', () async {
      // Daily, dormant since 40 days before "today" — the oldest ~10 of
      // those occurrences are >30 days stale, the last ~10 are not.
      final start = _today.subtract(const Duration(days: 40));
      await insertRule(id: 'r1', nextDueDate: start, frequency: 'daily');

      await engine.run(_householdId, asOf: _today);

      final expenses = await db.expenseDao.watchAll(_householdId).first;
      expect(expenses, isEmpty); // never auto-posted, regardless of age

      final rule = await db.recurringDao.findById('r1');
      final nextDueDate = rule!.nextDueDate.toUtc();
      final age = _today.difference(nextDueDate).inDays;
      expect(age, inInclusiveRange(0, 30));
      expect(nextDueDate.isAfter(start), isTrue); // it did advance
      expect(rule.lastPostedOn, isNull); // still nothing ever posted
    });

    test('a merely-due rule within the 30-day window is left completely '
        'untouched (still shows as pending)', () async {
      await insertRule(
        id: 'r1',
        nextDueDate: _today.subtract(const Duration(days: 5)),
        frequency: 'daily',
      );

      await engine.run(_householdId, asOf: _today);

      final rule = await db.recurringDao.findById('r1');
      expect(
        rule!.nextDueDate.toUtc(),
        _today.subtract(const Duration(days: 5)),
      );
    });
  });

  group('postOneOccurrence / skipOneOccurrence (T-9.5)', () {
    test(
      'postOneOccurrence creates a transaction and advances by one step',
      () async {
        await insertRule(id: 'r1', nextDueDate: DateTime.utc(2026, 6, 1));

        await engine.postOneOccurrence('r1');

        final expenses = await db.expenseDao.watchAll(_householdId).first;
        expect(expenses, hasLength(1));
        final rule = await db.recurringDao.findById('r1');
        expect(rule!.nextDueDate.toUtc(), DateTime.utc(2026, 7, 1));
        expect(rule.lastPostedOn!.toUtc(), DateTime.utc(2026, 6, 1));
      },
    );

    test('skipOneOccurrence advances without creating a transaction', () async {
      await insertRule(id: 'r1', nextDueDate: DateTime.utc(2026, 6, 1));

      await engine.skipOneOccurrence('r1');

      final expenses = await db.expenseDao.watchAll(_householdId).first;
      expect(expenses, isEmpty);
      final rule = await db.recurringDao.findById('r1');
      expect(rule!.nextDueDate.toUtc(), DateTime.utc(2026, 7, 1));
      expect(rule.lastPostedOn, isNull);
    });
  });
}
