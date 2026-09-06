import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/time/app_time.dart';
import '../../domain/models/income.dart' as domain;
import '../local/mappers/income_mapper.dart';
import '../sync/sync_engine.dart';

part 'income_repository.g.dart';

const _uuid = Uuid();

/// Income CRUD (spec §11.6, T-7.1): mirrors [ExpenseRepository]'s shape —
/// local-first read, every write goes to Drift + the outbox per the iron
/// rule (§9.1). Deliberately simpler than expenses: no duplicate guard, no
/// undo snackbar, no payment method — none of those are in scope for income.
class IncomeRepository {
  IncomeRepository(this._db, this._triggerSync);

  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<List<domain.Income>> watchAll(String householdId) => _db.incomeDao
      .watchAll(householdId)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Future<domain.Income?> findById(String id) async =>
      (await _db.incomeDao.findById(id))?.toDomain();

  Stream<domain.Income?> watchById(String id) =>
      _db.incomeDao.watchById(id).map((row) => row?.toDomain());

  /// [receivedOn] is derived from [receivedAt] via `AppTime.calendarDate` so
  /// the client and the server's `set_ist_date()` trigger never disagree
  /// about which calendar day the income falls on (same rule as expenses).
  Future<String> create({
    required String householdId,
    required String userId,
    required int amountPaise,
    String? categoryId,
    required DateTime receivedAt,
    String note = '',
    String source = '',
  }) async {
    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _save(
      domain.Income(
        id: id,
        householdId: householdId,
        userId: userId,
        amountPaise: amountPaise,
        categoryId: categoryId,
        receivedAt: receivedAt,
        receivedOn: AppTime.calendarDate(receivedAt),
        note: note,
        source: source,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> update(domain.Income income) => _save(
    income.copyWith(
      receivedOn: AppTime.calendarDate(income.receivedAt),
      updatedAt: DateTime.now().toUtc(),
    ),
  );

  Future<void> delete(String id) async {
    final now = DateTime.now().toUtc();
    await _db.incomeDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'income',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    _triggerSync();
  }

  Future<void> _save(domain.Income income) async {
    await _db.incomeDao.upsert(income.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'income',
        entityId: income.id,
        op: 'upsert',
        payload: jsonEncode(income.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
IncomeRepository incomeRepository(Ref ref) => IncomeRepository(
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);

/// All non-deleted income for the household, most recent first — backs the
/// Income List (T-7.2) and, in the future, Analytics.
@Riverpod(keepAlive: true)
Stream<List<domain.Income>> householdIncomes(Ref ref) =>
    ref.watch(incomeRepositoryProvider).watchAll(AppConstants.seedHouseholdId);
