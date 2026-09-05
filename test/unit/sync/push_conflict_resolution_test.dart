import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/logging/app_logger.dart';
import 'package:kharcha/data/remote/expense_remote_ds.dart';
import 'package:kharcha/data/sync/entity_sync_adapters.dart';

/// A scriptable [ExpenseRemoteDataSource] test double — records every call
/// and lets a test dictate exactly what the "server" currently holds,
/// without mocking Supabase's Postgrest builder chain (same precedent as
/// `FakeEntitySyncAdapter`).
class FakeExpenseRemoteDataSource implements ExpenseRemoteDataSource {
  @override
  final String table = 'expenses';

  /// What the compare-and-swap should report back: the server's resulting
  /// `updated_at` on success (which, per the real `touch_updated_at()`
  /// trigger, is not necessarily the payload's own claimed value — see the
  /// "server trigger advances past the payload" test below), or `null` to
  /// simulate a CAS mismatch (no rows matched).
  DateTime? casResult;

  /// What `fetchById` returns when the CAS above fails.
  Map<String, dynamic>? serverRow;

  DateTime? lastCasExpectedBase;
  final List<Map<String, dynamic>> plainUpserts = [];

  @override
  Future<DateTime?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    DateTime? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;

  @override
  Future<void> upsert(Map<String, dynamic> payload) async {
    plainUpserts.add(payload);
  }

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];

  @override
  Future<void> softDelete(String id, DateTime now) async {}
}

/// Spec §13 Test 5 / D12 at push time (see docs/DECISIONS.md, Gate 4
/// 2026-09-05 fix): a push must not silently clobber a genuinely newer edit
/// made by another device just because it happens to push second.
void main() {
  late AppDatabase db;
  late FakeExpenseRemoteDataSource remote;
  late ExpenseSyncAdapter adapter;

  const householdId = 'hh1';
  const userId = 'user1';
  const expenseId = 'exp1';

  Map<String, dynamic> payloadFor(DateTime updatedAt, {String note = 'edit'}) =>
      {
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
        'deleted_at': null,
      };

  Future<void> insertLocal({
    required DateTime updatedAt,
    required DateTime? baseUpdatedAt,
    required bool dirty,
    DateTime? localUpdatedAt,
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
        isDirty: Value(dirty),
        syncStatus: Value(dirty ? 'pending' : 'synced'),
        baseUpdatedAt: Value(baseUpdatedAt),
      ),
    );
  }

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    remote = FakeExpenseRemoteDataSource();
    adapter = ExpenseSyncAdapter(remote);
    AppLogger.instance.clear();
  });

  tearDown(() => db.close());

  test('a matching base pushes cleanly and stamps the new base', () async {
    final base = DateTime.utc(2026, 1, 1);
    final edited = DateTime.utc(2026, 1, 2);
    await insertLocal(
      updatedAt: edited,
      baseUpdatedAt: base,
      dirty: true,
      localUpdatedAt: edited,
    );
    remote.casResult = edited;

    await adapter.pushUpsert(db, payloadFor(edited));

    expect(remote.lastCasExpectedBase!.toUtc(), base);
    final local = await db.expenseDao.findById(expenseId);
    expect(local!.isDirty, isFalse);
    expect(local.baseUpdatedAt!.toUtc(), edited);
  });

  test('a conflict where the remote edit is newer discards the local edit and '
      'logs the loss — never silently overwritten by push order', () async {
    final base = DateTime.utc(2026, 1, 1);
    final localEditedAt = DateTime.utc(2026, 1, 2); // e.g. Vineet's edit
    final remoteEditedAt = DateTime.utc(2026, 1, 3); // Rupesh's newer edit
    await insertLocal(
      updatedAt: localEditedAt,
      baseUpdatedAt: base,
      dirty: true,
      localUpdatedAt: localEditedAt,
      note: 'local note',
    );
    remote.casResult = null;
    remote.serverRow = payloadFor(remoteEditedAt, note: 'remote note');

    await adapter.pushUpsert(db, payloadFor(localEditedAt));

    final local = await db.expenseDao.findById(expenseId);
    expect(local!.note, 'remote note');
    expect(local.isDirty, isFalse);
    expect(local.baseUpdatedAt!.toUtc(), remoteEditedAt);

    final logged = AppLogger.instance.recentEntries.any(
      (entry) =>
          entry.message.contains('conflict') &&
          entry.message.contains(expenseId),
    );
    expect(logged, isTrue, reason: 'the discarded local edit must be logged');
  });

  test('a conflict where the local edit is newer refreshes the base and '
      'requests a retry, without discarding the local edit', () async {
    final base = DateTime.utc(2026, 1, 1);
    final someoneElsesOlderEdit = DateTime.utc(2026, 1, 2);
    final localEditedAt = DateTime.utc(2026, 1, 3); // genuinely newest
    await insertLocal(
      updatedAt: localEditedAt,
      baseUpdatedAt: base,
      dirty: true,
      localUpdatedAt: localEditedAt,
      note: 'local note',
    );
    remote.casResult = null;
    remote.serverRow = payloadFor(
      someoneElsesOlderEdit,
      note: 'someone else\'s edit',
    );

    await expectLater(
      adapter.pushUpsert(db, payloadFor(localEditedAt)),
      throwsA(isA<SyncConflictRetryException>()),
    );

    final local = await db.expenseDao.findById(expenseId);
    expect(local!.note, 'local note', reason: 'the local edit is kept');
    expect(local.isDirty, isTrue);
    expect(
      local.baseUpdatedAt!.toUtc(),
      someoneElsesOlderEdit,
      reason: 'the base is refreshed so the next retry CASes correctly',
    );
    expect(AppLogger.instance.recentEntries, isEmpty);
  });

  test(
    'a dirty row with no local_updated_at (a pre-Gate-10-fix row, or any '
    'future write path that forgets to stamp it) does not crash on a CAS '
    'conflict — it logs with an "unknown time" placeholder and still '
    'resolves by adopting the remote row',
    () async {
      final base = DateTime.utc(2026, 1, 1);
      final remoteEditedAt = DateTime.utc(2026, 1, 3);
      await insertLocal(
        updatedAt: base,
        baseUpdatedAt: base,
        dirty: true,
        localUpdatedAt: null,
        note: 'local note',
      );
      remote.casResult = null;
      remote.serverRow = payloadFor(remoteEditedAt, note: 'remote note');

      await adapter.pushUpsert(db, payloadFor(base));

      final local = await db.expenseDao.findById(expenseId);
      expect(local!.note, 'remote note');
      expect(local.isDirty, isFalse);
      final logged = AppLogger.instance.recentEntries.any(
        (entry) =>
            entry.message.contains('conflict') &&
            entry.message.contains(expenseId),
      );
      expect(logged, isTrue);
    },
  );

  test('a brand-new row (no base yet) pushes unconditionally', () async {
    final now = DateTime.utc(2026, 1, 1);
    await insertLocal(
      updatedAt: now,
      baseUpdatedAt: null,
      dirty: true,
      localUpdatedAt: now,
    );
    remote.casResult = now;

    await adapter.pushUpsert(db, payloadFor(now));

    expect(remote.lastCasExpectedBase, isNull);
    final local = await db.expenseDao.findById(expenseId);
    expect(local!.isDirty, isFalse);
    expect(local.baseUpdatedAt!.toUtc(), now);
  });

  test(
    'two same-device edits queued before either syncs both survive, even '
    'when the server trigger advances updated_at past what each payload '
    'claimed (Gate 10 2026-09-05 fix)',
    () async {
      // Mirrors `touch_updated_at()`'s GREATEST(now(), incoming): after being
      // offline, the server's real clock is later than either edit's
      // client-side timestamp, so it stamps its own value on every write —
      // never exactly what the payload claimed.
      final t0 = DateTime.utc(2026, 1, 1, 0, 0);
      final t1 = DateTime.utc(2026, 1, 1, 0, 1);
      final serverNowAtFirstPush = DateTime.utc(2026, 1, 1, 0, 10);
      final serverNowAtSecondPush = DateTime.utc(2026, 1, 1, 0, 11);

      await insertLocal(
        updatedAt: t1,
        baseUpdatedAt: null,
        dirty: true,
        localUpdatedAt: t1,
        note: 'has_receipt=true edit',
      );

      // Entry #1: the original create, queued first, payload frozen at t0.
      remote.casResult = serverNowAtFirstPush;
      await adapter.pushUpsert(db, payloadFor(t0, note: 'create'));

      final afterFirstPush = await db.expenseDao.findById(expenseId);
      expect(
        afterFirstPush!.baseUpdatedAt!.toUtc(),
        serverNowAtFirstPush,
        reason:
            'the new base must be what the server actually stored, not the '
            "payload's stale t0 claim",
      );

      // Entry #2: the has_receipt edit, queued second, payload frozen at t1.
      // Its CAS check must be against serverNowAtFirstPush (the corrected
      // base) — which is exactly what a real second CAS call would match,
      // so this must succeed rather than be treated as a remote conflict.
      remote.casResult = serverNowAtSecondPush;
      await adapter.pushUpsert(db, payloadFor(t1, note: 'has_receipt=true edit'));

      expect(
        remote.lastCasExpectedBase!.toUtc(),
        serverNowAtFirstPush,
        reason: "the second push's CAS must target the real server value",
      );
      final afterSecondPush = await db.expenseDao.findById(expenseId);
      expect(
        afterSecondPush!.note,
        'has_receipt=true edit',
        reason:
            'the second edit must not be silently discarded as a spurious '
            "conflict with the device's own first push",
      );
      expect(afterSecondPush.isDirty, isFalse);
      expect(afterSecondPush.baseUpdatedAt!.toUtc(), serverNowAtSecondPush);
      expect(
        AppLogger.instance.recentEntries,
        isEmpty,
        reason: 'no conflict was ever genuinely lost, so nothing is logged',
      );
    },
  );
}
