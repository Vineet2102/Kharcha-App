import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/expense.dart' as domain;
import '../../domain/models/income.dart' as domain;
import '../../domain/models/recurring_rule.dart' as domain;
import '../../domain/models/recurring_schedule.dart';
import '../local/mappers/expense_mapper.dart';
import '../local/mappers/income_mapper.dart';
import '../local/mappers/recurring_rule_mapper.dart';

part 'recurring_posting_engine.g.dart';

const _uuid = Uuid();

/// The recurring posting engine (spec §11.8, T-9.3): called once per
/// [SyncEngine] cycle, right after the pull — so an occurrence another
/// device already posted for the same rule is visible locally *before* this
/// device decides whether to post its own (T-9.4's cross-device race is
/// still resolved at the outbox layer for the case that slips through, but
/// pulling first closes most of the window).
///
/// For every active due rule:
/// - **auto-post**: creates every occurrence up to today, capped at
///   [catchUpCap] per run (a rule dormant for years catches up over several
///   sync cycles rather than in one runaway loop), then advances
///   `next_due_date` past all of them.
/// - **manual**: does *not* create anything or advance `next_due_date` — a
///   due rule simply stays visible via `RecurringDao.dueOn` as a pending
///   confirmation until the user taps Post or Skip on the Dashboard card
///   (T-9.5, see [postOneOccurrence]/[skipOneOccurrence]) — except an
///   occurrence more than [pendingExpiryDays] old, which is silently
///   skipped without asking (spec §11.8's "pending confirmations expire
///   after 30 days").
class RecurringPostingEngine {
  RecurringPostingEngine(this._db);

  final AppDatabase _db;

  static const catchUpCap = 24;
  static const pendingExpiryDays = 30;

  /// [asOf] defaults to today (IST) — overridable so tests don't depend on
  /// the real wall clock, mirroring `RecurringDao.dueOn`'s own signature.
  Future<void> run(String householdId, {DateTime? asOf}) async {
    final today = asOf ?? AppTime.calendarDate(DateTime.now().toUtc());
    final dueRows = await _db.recurringDao.dueOn(householdId, today);
    for (final row in dueRows) {
      await _processRule(row.toDomain(), today);
    }
  }

  Future<void> _processRule(domain.RecurringRule rule, DateTime today) async {
    final schedule = dueOccurrencesFor(
      nextDueDate: rule.nextDueDate,
      asOf: today,
      frequency: rule.frequency,
      intervalN: rule.intervalN,
      dayOfMonth: rule.dayOfMonth,
      endDate: rule.endDate,
      maxOccurrences: catchUpCap,
    );
    if (schedule.occurrences.isEmpty) {
      if (schedule.ruleExpired) await _deactivate(rule);
      return;
    }

    if (rule.autoPost) {
      for (final occurrence in schedule.occurrences) {
        await _createOccurrence(rule, occurrence);
      }
      await _persistRule(
        rule,
        nextDueDate: schedule.nextDueDate,
        lastPostedOn: schedule.occurrences.last,
        deactivate: schedule.ruleExpired,
      );
      return;
    }

    // Manual rule: silently skip past anything too stale to still ask
    // about, but leave the earliest still-askable occurrence exactly where
    // it is (frozen at `next_due_date`) so it keeps showing as pending —
    // nothing to persist if none of the catch-up batch is stale yet.
    final cutoff = today.subtract(const Duration(days: pendingExpiryDays));
    var staleCount = 0;
    while (staleCount < schedule.occurrences.length &&
        schedule.occurrences[staleCount].isBefore(cutoff)) {
      staleCount++;
    }
    if (staleCount == 0) return;
    final allStale = staleCount == schedule.occurrences.length;
    await _persistRule(
      rule,
      nextDueDate: allStale
          ? schedule.nextDueDate
          : schedule.occurrences[staleCount],
      lastPostedOn: rule.lastPostedOn,
      deactivate: allStale && schedule.ruleExpired,
    );
  }

  /// The Dashboard's pending-confirmations "Post" button (T-9.5): posts
  /// exactly the one occurrence currently sitting at `next_due_date` and
  /// advances it by a single step. If several occurrences are overdue, the
  /// rule simply stays due afterwards and the card shows it again.
  Future<void> postOneOccurrence(String ruleId) async {
    final row = await _db.recurringDao.findById(ruleId);
    if (row == null) return;
    final rule = row.toDomain();
    final occurrence = rule.nextDueDate;
    await _createOccurrence(rule, occurrence);
    final next = advanceDueDate(
      from: occurrence,
      frequency: rule.frequency,
      intervalN: rule.intervalN,
      dayOfMonth: rule.dayOfMonth,
    );
    await _persistRule(
      rule,
      nextDueDate: next,
      lastPostedOn: occurrence,
      deactivate: rule.endDate != null && next.isAfter(rule.endDate!),
    );
  }

  /// The Dashboard's pending-confirmations "Skip" button (T-9.5): advances
  /// `next_due_date` by a single step without creating a transaction.
  Future<void> skipOneOccurrence(String ruleId) async {
    final row = await _db.recurringDao.findById(ruleId);
    if (row == null) return;
    final rule = row.toDomain();
    final next = advanceDueDate(
      from: rule.nextDueDate,
      frequency: rule.frequency,
      intervalN: rule.intervalN,
      dayOfMonth: rule.dayOfMonth,
    );
    await _persistRule(
      rule,
      nextDueDate: next,
      lastPostedOn: rule.lastPostedOn,
      deactivate: rule.endDate != null && next.isAfter(rule.endDate!),
    );
  }

  /// Creates [occurrence] for [rule] directly at the Drift+outbox layer
  /// (spec §9.1's iron rule) rather than through `ExpenseRepository`/
  /// `IncomeRepository` — those add duplicate-guard dialogs and an undo
  /// snackbar that make no sense for a background/automatic post.
  /// [rule.title] carries the identity that expenses/incomes have no
  /// dedicated field for: it becomes the expense's `merchant` (and the
  /// income's `source`), and also backs `note` whenever the rule's own note
  /// is empty, so a posted occurrence is never just a bare, unlabelled
  /// amount under "Uncategorised".
  ///
  /// Idempotent per (rule, occurrence): if a matching row already exists
  /// locally — e.g. the app was killed after this ran but before
  /// `next_due_date` was persisted — this is a no-op, protecting against
  /// re-creating it on the next run. The cross-*device* case (two phones
  /// racing to post the same occurrence) is instead resolved by
  /// `OutboxProcessor` catching the server's unique-index violation
  /// (T-9.4).
  Future<void> _createOccurrence(
    domain.RecurringRule rule,
    DateTime occurrence,
  ) async {
    final now = DateTime.now().toUtc();
    if (rule.kind == TxnKind.expense) {
      if (await _db.expenseDao.findByOccurrence(rule.id, occurrence) != null) {
        return;
      }
      final expense = domain.Expense(
        id: _uuid.v4(),
        householdId: rule.householdId,
        userId: rule.userId,
        amountPaise: rule.amountPaise,
        categoryId: rule.categoryId,
        paymentMethodId: rule.paymentMethodId,
        spentAt: occurrence,
        spentOn: occurrence,
        note: rule.note.isNotEmpty ? rule.note : rule.title,
        merchant: rule.title,
        recurringRuleId: rule.id,
        occurrenceDate: occurrence,
        createdAt: now,
        updatedAt: now,
      );
      await _db.expenseDao.upsert(expense.toCompanion(dirty: true));
      await _enqueue('expense', expense.id, expense.toJson());
    } else {
      if (await _db.incomeDao.findByOccurrence(rule.id, occurrence) != null) {
        return;
      }
      final income = domain.Income(
        id: _uuid.v4(),
        householdId: rule.householdId,
        userId: rule.userId,
        amountPaise: rule.amountPaise,
        categoryId: rule.categoryId,
        receivedAt: occurrence,
        receivedOn: occurrence,
        note: rule.note,
        source: rule.title,
        recurringRuleId: rule.id,
        occurrenceDate: occurrence,
        createdAt: now,
        updatedAt: now,
      );
      await _db.incomeDao.upsert(income.toCompanion(dirty: true));
      await _enqueue('income', income.id, income.toJson());
    }
  }

  Future<void> _deactivate(domain.RecurringRule rule) => _persistRule(
    rule,
    nextDueDate: rule.nextDueDate,
    lastPostedOn: rule.lastPostedOn,
    deactivate: true,
  );

  Future<void> _persistRule(
    domain.RecurringRule rule, {
    required DateTime nextDueDate,
    required DateTime? lastPostedOn,
    required bool deactivate,
  }) async {
    if (deactivate) {
      AppLogger.instance.warn(
        'Recurring rule ${rule.id} reached its end date — deactivating.',
      );
    }
    final updated = rule.copyWith(
      nextDueDate: nextDueDate,
      lastPostedOn: lastPostedOn,
      isActive: deactivate ? false : rule.isActive,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.recurringDao.upsert(updated.toCompanion(dirty: true));
    await _enqueue('recurring_rule', updated.id, updated.toJson());
  }

  Future<void> _enqueue(
    String entity,
    String entityId,
    Map<String, dynamic> json,
  ) => _db.outboxDao.enqueue(
    OutboxEntriesCompanion.insert(
      id: _uuid.v4(),
      entity: entity,
      entityId: entityId,
      op: 'upsert',
      payload: jsonEncode(json),
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

@Riverpod(keepAlive: true)
RecurringPostingEngine recurringPostingEngine(Ref ref) =>
    RecurringPostingEngine(ref.watch(appDatabaseProvider));
