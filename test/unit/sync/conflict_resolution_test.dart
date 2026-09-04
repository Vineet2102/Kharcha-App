import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/logging/app_logger.dart';
import 'package:kharcha/data/remote/expense_remote_ds.dart';
import 'package:kharcha/data/sync/entity_sync_adapters.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Spec §13 Test 5: "Editing offline, then receiving a newer remote edit,
/// resolves per D12 without data loss on the losing side (the losing
/// version is logged)." Exercises `ExpenseSyncAdapter.pullApply` directly —
/// it never touches the network, so no remote mock stubbing is needed.
void main() {
  late AppDatabase db;
  late ExpenseSyncAdapter adapter;

  const householdId = 'hh1';
  const userId = 'user1';
  const expenseId = 'exp1';

  Map<String, dynamic> remoteJson({
    required DateTime updatedAt,
    String note = 'remote note',
    DateTime? deletedAt,
  }) => {
    'id': expenseId,
    'household_id': householdId,
    'user_id': userId,
    'amount_paise': 5000,
    'category_id': null,
    'payment_method_id': null,
    'spent_at': updatedAt.toIso8601String(),
    'spent_on': updatedAt.toIso8601String(),
    'note': note,
    'merchant': '',
    'has_receipt': false,
    'recurring_rule_id': null,
    'occurrence_date': null,
    'created_by_device': null,
    'created_at': updatedAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'deleted_at': deletedAt?.toIso8601String(),
  };

  Future<void> insertDirtyLocal({
    required DateTime updatedAt,
    required DateTime localUpdatedAt,
    String note = 'local note',
  }) {
    return db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: expenseId,
        householdId: householdId,
        userId: userId,
        amountPaise: 5000,
        spentAt: updatedAt,
        spentOn: updatedAt,
        note: Value(note),
        createdAt: updatedAt,
        updatedAt: updatedAt,
        localUpdatedAt: Value(localUpdatedAt),
        isDirty: const Value(true),
        syncStatus: const Value('pending'),
      ),
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    adapter = ExpenseSyncAdapter(ExpenseRemoteDataSource(MockSupabaseClient()));
    AppLogger.instance.clear();
  });

  tearDown(() => db.close());

  test('a dirty local row newer than the remote row is kept as-is', () async {
    final localEditedAt = DateTime.utc(2026, 1, 2);
    final remoteUpdatedAt = DateTime.utc(
      2026,
      1,
      1,
    ); // older than the local edit
    await insertDirtyLocal(
      updatedAt: DateTime.utc(2026, 1, 1),
      localUpdatedAt: localEditedAt,
    );

    await adapter.pullApply(db, remoteJson(updatedAt: remoteUpdatedAt));

    final local = await db.expenseDao.findById(expenseId);
    expect(local!.note, 'local note');
    expect(local.isDirty, isTrue);
  });

  test('a newer remote row overwrites a dirty local row and logs the discarded edit', () async {
    final localEditedAt = DateTime.utc(2026, 1, 1);
    final remoteUpdatedAt = DateTime.utc(
      2026,
      1,
      2,
    ); // newer than the local edit
    await insertDirtyLocal(
      updatedAt: DateTime.utc(2026, 1, 1),
      localUpdatedAt: localEditedAt,
    );

    await adapter.pullApply(
      db,
      remoteJson(updatedAt: remoteUpdatedAt, note: 'remote note'),
    );

    final local = await db.expenseDao.findById(expenseId);
    expect(local!.note, 'remote note');
    expect(local.isDirty, isFalse);

    final logged = AppLogger.instance.recentEntries.any(
      (entry) =>
          entry.message.contains('conflict') &&
          entry.message.contains(expenseId),
    );
    expect(logged, isTrue, reason: 'the discarded local edit must be logged');
  });

  test('a clean (non-dirty) local row is silently overwritten by remote, no loss logged', () async {
    await db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: expenseId,
        householdId: householdId,
        userId: userId,
        amountPaise: 5000,
        spentAt: DateTime.utc(2026, 1, 1),
        spentOn: DateTime.utc(2026, 1, 1),
        note: const Value('stale synced note'),
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      ),
    );

    await adapter.pullApply(
      db,
      remoteJson(
        updatedAt: DateTime.utc(2026, 1, 2),
        note: 'fresh remote note',
      ),
    );

    final local = await db.expenseDao.findById(expenseId);
    expect(local!.note, 'fresh remote note');
    expect(AppLogger.instance.recentEntries, isEmpty);
  });

  test('a tombstoned remote row deletes the local row', () async {
    await insertDirtyLocal(
      updatedAt: DateTime.utc(2026, 1, 1),
      localUpdatedAt: DateTime.utc(2026, 1, 1),
    );

    await adapter.pullApply(
      db,
      remoteJson(
        updatedAt: DateTime.utc(2026, 1, 2),
        deletedAt: DateTime.utc(2026, 1, 2),
      ),
    );

    expect(await db.expenseDao.findById(expenseId), isNull);
  });
}
