import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/expense.dart' as domain;
import '../../domain/models/expense_filter.dart';
import '../local/mappers/expense_mapper.dart';
import '../sync/sync_engine.dart';

part 'expense_repository.g.dart';

const _uuid = Uuid();

/// Expense CRUD (spec §11.2/§11.3, T-5.4): local-first read (Drift streams),
/// every write goes to Drift + the outbox per the iron rule (§9.1) — this
/// repository never touches Supabase directly.
class ExpenseRepository {
  ExpenseRepository(this._db, this._triggerSync);

  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<List<domain.Expense>> watchFiltered({
    required String householdId,
    required ExpenseFilter filter,
    required int limit,
  }) => _db.expenseDao
      .watchFiltered(householdId: householdId, filter: filter, limit: limit)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Stream<int> watchFilteredTotal({
    required String householdId,
    required ExpenseFilter filter,
  }) => _db.expenseDao.watchFilteredTotal(householdId: householdId, filter: filter);

  Future<domain.Expense?> findById(String id) async =>
      (await _db.expenseDao.findById(id))?.toDomain();

  Stream<domain.Expense?> watchById(String id) =>
      _db.expenseDao.watchById(id).map((row) => row?.toDomain());

  Future<bool> hasPossibleDuplicate({
    required String householdId,
    required String userId,
    required int amountPaise,
    required String? categoryId,
    required DateTime spentAt,
    String? excludingId,
  }) => _db.expenseDao.hasPossibleDuplicate(
    householdId: householdId,
    userId: userId,
    amountPaise: amountPaise,
    categoryId: categoryId,
    spentAt: spentAt,
    excludingId: excludingId,
  );

  Future<String?> lastUsedPaymentMethodId(String userId) =>
      _db.expenseDao.lastUsedPaymentMethodId(userId);

  Future<List<String>> mostUsedCategoryIds(String userId) =>
      _db.expenseDao.mostUsedCategoryIds(userId);

  Future<List<String>> recentDistinctNotes(String userId) =>
      _db.expenseDao.recentDistinctNotes(userId);

  Future<List<String>> recentDistinctMerchants(String userId) =>
      _db.expenseDao.recentDistinctMerchants(userId);

  /// [spentOn] is derived from [spentAt] via `AppTime.calendarDate` so the
  /// client and the server's `set_ist_date()` trigger never disagree about
  /// which calendar day the expense falls on.
  Future<String> create({
    required String householdId,
    required String userId,
    required int amountPaise,
    String? categoryId,
    String? paymentMethodId,
    required DateTime spentAt,
    String note = '',
    String merchant = '',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _save(
      domain.Expense(
        id: id,
        householdId: householdId,
        userId: userId,
        amountPaise: amountPaise,
        categoryId: categoryId,
        paymentMethodId: paymentMethodId,
        spentAt: spentAt,
        spentOn: AppTime.calendarDate(spentAt),
        note: note,
        merchant: merchant,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(domain.Expense expense) => _save(
    expense.copyWith(
      spentOn: AppTime.calendarDate(expense.spentAt),
      updatedAt: DateTime.now().toUtc(),
    ),
  );

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await _db.expenseDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'expense',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    _triggerSync();
  }

  /// Undo for the 5 s "Saved ✓" snackbar (spec §11.2). If the create's
  /// outbox entry hasn't been pushed yet, it's simply removed — the server
  /// never sees the expense at all. Otherwise the row is soft-deleted and a
  /// real delete is enqueued so the undo still propagates on the next sync.
  Future<void> undoCreate(String id) async {
    final now = DateTime.now().toUtc();
    final removedBeforePush = await _db.outboxDao.removePendingUpsert(
      'expense',
      id,
    );
    await _db.expenseDao.softDelete(id, now);
    if (!removedBeforePush) {
      await _db.outboxDao.enqueue(
        OutboxEntriesCompanion.insert(
          id: _uuid.v4(),
          entity: 'expense',
          entityId: id,
          op: 'delete',
          payload: '{}',
          createdAt: now,
        ),
      );
    }
    _triggerSync();
  }

  Future<void> _save(domain.Expense expense) async {
    await _db.expenseDao.upsert(expense.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'expense',
        entityId: expense.id,
        op: 'upsert',
        payload: jsonEncode(expense.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
ExpenseRepository expenseRepository(Ref ref) => ExpenseRepository(
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);
