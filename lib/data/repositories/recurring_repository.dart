import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/recurring_rule.dart' as domain;
import '../../domain/models/recurring_schedule.dart' as schedule;
import '../local/mappers/recurring_rule_mapper.dart';
import '../sync/recurring_posting_engine.dart';
import '../sync/sync_engine.dart';

part 'recurring_repository.g.dart';

const _uuid = Uuid();

/// Recurring rule CRUD (spec §11.8, T-9.2): local-first read, every write
/// goes to Drift + the outbox per the iron rule (§9.1). RLS (`rec_write`):
/// own rule, or admin — mirrored client-side by the editor forcing
/// `userId` to the signed-in member unless they're an admin, same shape as
/// `BudgetRepository`'s scope check.
class RecurringRepository {
  RecurringRepository(this._db, this._postingEngine, this._triggerSync);

  final AppDatabase _db;
  final RecurringPostingEngine _postingEngine;
  final void Function() _triggerSync;

  Stream<List<domain.RecurringRule>> watchAll(String householdId) => _db
      .recurringDao
      .watchAll(householdId)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Future<domain.RecurringRule?> findById(String id) async =>
      (await _db.recurringDao.findById(id))?.toDomain();

  /// The rule editor's live preview (T-9.2): the next [count] occurrences
  /// from [from] — the form's `start_date` for a new rule, or the existing
  /// rule's `next_due_date` when editing one.
  List<DateTime> previewOccurrences({
    required DateTime from,
    required RecurFrequency frequency,
    required int intervalN,
    int? dayOfMonth,
    DateTime? endDate,
    int count = 3,
  }) => schedule.previewOccurrences(
    from: from,
    frequency: frequency,
    intervalN: intervalN,
    dayOfMonth: dayOfMonth,
    endDate: endDate,
    count: count,
  );

  Future<String> create({
    required String householdId,
    required String userId,
    required TxnKind kind,
    required String title,
    required int amountPaise,
    String? categoryId,
    String? paymentMethodId,
    String note = '',
    required RecurFrequency frequency,
    int intervalN = 1,
    int? dayOfMonth,
    int? weekday,
    int? monthOfYear,
    required DateTime startDate,
    DateTime? endDate,
    bool autoPost = false,
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _save(
      domain.RecurringRule(
        id: id,
        householdId: householdId,
        userId: userId,
        kind: kind,
        title: title,
        amountPaise: amountPaise,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        note: note,
        frequency: frequency,
        intervalN: intervalN,
        dayOfMonth: dayOfMonth,
        weekday: weekday,
        monthOfYear: monthOfYear,
        startDate: startDate,
        endDate: endDate,
        // The first occurrence hasn't happened yet — the posting engine
        // takes it from here (T-9.3).
        nextDueDate: startDate,
        autoPost: autoPost,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(domain.RecurringRule rule) =>
      _save(rule.copyWith(updatedAt: DateTime.now().toUtc()));

  /// Soft-deletes the rule. Per spec §11.8: "deleting a rule never deletes
  /// already-posted transactions; it only stops future ones" — those rows
  /// keep their own independent lifecycle, `recurring_rule_id` simply
  /// pointing at a now-gone rule.
  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await _db.recurringDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'recurring_rule',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    _triggerSync();
  }

  /// Dashboard "Post" button (T-9.5).
  Future<void> postPending(String ruleId) async {
    await _postingEngine.postOneOccurrence(ruleId);
    _triggerSync();
  }

  /// Dashboard "Skip" button (T-9.5).
  Future<void> skipPending(String ruleId) async {
    await _postingEngine.skipOneOccurrence(ruleId);
    _triggerSync();
  }

  Future<void> _save(domain.RecurringRule rule) async {
    await _db.recurringDao.upsert(rule.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'recurring_rule',
        entityId: rule.id,
        op: 'upsert',
        payload: jsonEncode(rule.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
RecurringRepository recurringRepository(Ref ref) => RecurringRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(recurringPostingEngineProvider),
  () => ref.read(syncEngineProvider).sync(),
);

/// All non-deleted recurring rules for the household — backs the Recurring
/// List (T-9.2) and the Dashboard's pending-confirmations card (T-9.5).
@Riverpod(keepAlive: true)
Stream<List<domain.RecurringRule>> householdRecurringRules(Ref ref) => ref
    .watch(recurringRepositoryProvider)
    .watchAll(AppConstants.seedHouseholdId);
