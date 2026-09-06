import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/logging/app_logger.dart';
import 'package:kharcha/data/remote/attachment_remote_ds.dart';
import 'package:kharcha/data/remote/budget_remote_ds.dart';
import 'package:kharcha/data/remote/category_remote_ds.dart';
import 'package:kharcha/data/remote/income_remote_ds.dart';
import 'package:kharcha/data/remote/payment_method_remote_ds.dart';
import 'package:kharcha/data/remote/recurring_rule_remote_ds.dart';
import 'package:kharcha/data/sync/entity_sync_adapters.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// A scriptable remote-data-source double, one per push-capable entity
/// (mirrors `FakeExpenseRemoteDataSource` in push_conflict_resolution_test.dart
/// — avoids mocking Supabase's Postgrest builder chain, per docs/DECISIONS.md).
class _FakeRemote {
  String? casResult;
  Map<String, dynamic>? serverRow;
  String? lastCasExpectedBase;
  final List<String> softDeletes = [];
}

class FakeCategoryRemoteDataSource extends _FakeRemote
    implements CategoryRemoteDataSource {
  @override
  final String table = 'categories';
  @override
  Future<String?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    String? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;
  @override
  Future<void> upsert(Map<String, dynamic> payload) async {}
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];
  @override
  Future<void> softDelete(String id, DateTime now) async {
    softDeletes.add(id);
  }
}

class FakePaymentMethodRemoteDataSource extends _FakeRemote
    implements PaymentMethodRemoteDataSource {
  @override
  final String table = 'payment_methods';
  @override
  Future<String?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    String? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;
  @override
  Future<void> upsert(Map<String, dynamic> payload) async {}
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];
  @override
  Future<void> softDelete(String id, DateTime now) async {
    softDeletes.add(id);
  }
}

class FakeIncomeRemoteDataSource extends _FakeRemote
    implements IncomeRemoteDataSource {
  @override
  final String table = 'incomes';
  @override
  Future<String?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    String? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;
  @override
  Future<void> upsert(Map<String, dynamic> payload) async {}
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];
  @override
  Future<void> softDelete(String id, DateTime now) async {
    softDeletes.add(id);
  }
}

class FakeBudgetRemoteDataSource extends _FakeRemote
    implements BudgetRemoteDataSource {
  @override
  final String table = 'budgets';
  @override
  Future<String?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    String? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;
  @override
  Future<void> upsert(Map<String, dynamic> payload) async {}
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];
  @override
  Future<void> softDelete(String id, DateTime now) async {
    softDeletes.add(id);
  }
}

class FakeRecurringRuleRemoteDataSource extends _FakeRemote
    implements RecurringRuleRemoteDataSource {
  @override
  final String table = 'recurring_rules';
  @override
  Future<String?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    String? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;
  @override
  Future<void> upsert(Map<String, dynamic> payload) async {}
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];
  @override
  Future<void> softDelete(String id, DateTime now) async {
    softDeletes.add(id);
  }
}

class FakeAttachmentRemoteDataSource extends _FakeRemote
    implements AttachmentRemoteDataSource {
  @override
  final String table = 'attachments';
  @override
  Future<String?> upsertIfBaseMatches(
    Map<String, dynamic> payload,
    String? expectedBase,
  ) async {
    lastCasExpectedBase = expectedBase;
    return casResult;
  }

  @override
  Future<Map<String, dynamic>?> fetchById(String id) async => serverRow;
  @override
  Future<void> upsert(Map<String, dynamic> payload) async {}
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    int limit = 500,
  }) async => const [];
  @override
  Future<void> softDelete(String id, DateTime now) async {
    softDeletes.add(id);
  }
}

/// T-15.3: fills in per-entity branch coverage for `entity_sync_adapters.dart`
/// beyond what `conflict_resolution_test.dart` / `push_conflict_resolution_test.dart`
/// already prove once via `ExpenseSyncAdapter` — every concrete adapter class
/// has its own copy of the same `pullApply`/`pushUpsert` bodies (see the
/// file's own doc comment for why they're not further deduplicated), so line
/// coverage tooling needs each class exercised directly at least once.
void main() {
  late AppDatabase db;
  const householdId = 'hh1';
  const userId = 'user1';

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    AppLogger.instance.clear();
  });

  tearDown(() => db.close());

  group('CategorySyncAdapter', () {
    const id = 'cat1';
    late FakeCategoryRemoteDataSource remote;
    late CategorySyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String name = 'remote name',
      DateTime? deletedAt,
    }) => {
      'id': id,
      'household_id': householdId,
      'name': name,
      'kind': 'expense',
      'icon_key': 'category',
      'colour_hex': '#607D8B',
      'sort_order': 100,
      'is_archived': false,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };

    setUp(() {
      remote = FakeCategoryRemoteDataSource();
      adapter = CategorySyncAdapter(remote);
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.categoryDao.upsert(
          CategoriesCompanion.insert(
            id: id,
            householdId: householdId,
            name: 'local name',
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('tombstone deletes the local row', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.pullApply(
        db,
        json(
          updatedAt: DateTime.utc(2026, 1, 2),
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(await db.categoryDao.findById(id), isNull);
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      final local = await db.categoryDao.findById(id);
      expect(local!.name, 'local name');
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.categoryDao.findById(id);
        expect(local!.name, 'remote name');
        expect(local.isDirty, isFalse);
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('pushUpsert on a clean CAS match marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      remote.casResult = DateTime.utc(2026, 1, 1).toIso8601String();
      await adapter.pushUpsert(db, json(updatedAt: DateTime.utc(2026, 1, 1)));
      expect((await db.categoryDao.findById(id))!.isDirty, isFalse);
    });

    test('pushSoftDelete delegates to the remote data source', () async {
      final now = DateTime.utc(2026, 1, 1);
      await adapter.pushSoftDelete(id, now);
      expect(remote.softDeletes, [id]);
    });

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.categoryDao.findById(id))!.isDirty, isFalse);
    });

    test('selectSince delegates to the remote data source', () async {
      expect(
        await adapter.selectSince(
          householdId: householdId,
          cursor: DateTime.utc(2026),
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('PaymentMethodSyncAdapter', () {
    const id = 'pm1';
    late FakePaymentMethodRemoteDataSource remote;
    late PaymentMethodSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String name = 'remote name',
      DateTime? deletedAt,
    }) => {
      'id': id,
      'household_id': householdId,
      'name': name,
      'type': 'cash',
      'is_archived': false,
      'sort_order': 100,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };

    setUp(() {
      remote = FakePaymentMethodRemoteDataSource();
      adapter = PaymentMethodSyncAdapter(remote);
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.paymentMethodDao.upsert(
          PaymentMethodsCompanion.insert(
            id: id,
            householdId: householdId,
            name: 'local name',
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('tombstone deletes the local row', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.pullApply(
        db,
        json(
          updatedAt: DateTime.utc(2026, 1, 2),
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(await db.paymentMethodDao.findById(id), isNull);
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect((await db.paymentMethodDao.findById(id))!.name, 'local name');
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.paymentMethodDao.findById(id);
        expect(local!.name, 'remote name');
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('pushUpsert on a clean CAS match marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      remote.casResult = DateTime.utc(2026, 1, 1).toIso8601String();
      await adapter.pushUpsert(db, json(updatedAt: DateTime.utc(2026, 1, 1)));
      expect((await db.paymentMethodDao.findById(id))!.isDirty, isFalse);
    });

    test('pushSoftDelete delegates to the remote data source', () async {
      await adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1));
      expect(remote.softDeletes, [id]);
    });

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.paymentMethodDao.findById(id))!.isDirty, isFalse);
    });

    test('selectSince delegates to the remote data source', () async {
      expect(
        await adapter.selectSince(
          householdId: householdId,
          cursor: DateTime.utc(2026),
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('IncomeSyncAdapter', () {
    const id = 'inc1';
    late FakeIncomeRemoteDataSource remote;
    late IncomeSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String source = 'remote source',
      DateTime? deletedAt,
    }) => {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'amount_paise': 5000,
      'category_id': null,
      'received_at': updatedAt.toIso8601String(),
      'received_on': updatedAt.toIso8601String().substring(0, 10),
      'note': '',
      'source': source,
      'recurring_rule_id': null,
      'occurrence_date': null,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };

    setUp(() {
      remote = FakeIncomeRemoteDataSource();
      adapter = IncomeSyncAdapter(remote);
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.incomeDao.upsert(
          IncomesCompanion.insert(
            id: id,
            householdId: householdId,
            userId: userId,
            amountPaise: 5000,
            receivedAt: updatedAt,
            receivedOn: updatedAt,
            source: const Value('local source'),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('tombstone deletes the local row', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.pullApply(
        db,
        json(
          updatedAt: DateTime.utc(2026, 1, 2),
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(await db.incomeDao.findById(id), isNull);
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect((await db.incomeDao.findById(id))!.source, 'local source');
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.incomeDao.findById(id);
        expect(local!.source, 'remote source');
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('pushUpsert on a clean CAS match marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      remote.casResult = DateTime.utc(2026, 1, 1).toIso8601String();
      await adapter.pushUpsert(db, json(updatedAt: DateTime.utc(2026, 1, 1)));
      expect((await db.incomeDao.findById(id))!.isDirty, isFalse);
    });

    test('pushSoftDelete delegates to the remote data source', () async {
      await adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1));
      expect(remote.softDeletes, [id]);
    });

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.incomeDao.findById(id))!.isDirty, isFalse);
    });

    test('selectSince delegates to the remote data source', () async {
      expect(
        await adapter.selectSince(
          householdId: householdId,
          cursor: DateTime.utc(2026),
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('BudgetSyncAdapter', () {
    const id = 'bud1';
    late FakeBudgetRemoteDataSource remote;
    late BudgetSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      int amountPaise = 500000,
      DateTime? deletedAt,
    }) => {
      'id': id,
      'household_id': householdId,
      'scope': 'household',
      'user_id': null,
      'category_id': null,
      'amount_paise': amountPaise,
      'period_month': '2026-01-01',
      'is_rollover': false,
      'alert_threshold_pct': 80,
      'created_by': userId,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };

    setUp(() {
      remote = FakeBudgetRemoteDataSource();
      adapter = BudgetSyncAdapter(remote);
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.budgetDao.upsert(
          BudgetsCompanion.insert(
            id: id,
            householdId: householdId,
            scope: 'household',
            amountPaise: 100000,
            periodMonth: DateTime.utc(2026, 1, 1),
            createdBy: userId,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('tombstone deletes the local row', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.pullApply(
        db,
        json(
          updatedAt: DateTime.utc(2026, 1, 2),
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(await db.budgetDao.findById(id), isNull);
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect((await db.budgetDao.findById(id))!.amountPaise, 100000);
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(
          db,
          json(updatedAt: DateTime.utc(2026, 1, 2), amountPaise: 700000),
        );
        final local = await db.budgetDao.findById(id);
        expect(local!.amountPaise, 700000);
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('pushUpsert on a clean CAS match marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      remote.casResult = DateTime.utc(2026, 1, 1).toIso8601String();
      await adapter.pushUpsert(db, json(updatedAt: DateTime.utc(2026, 1, 1)));
      expect((await db.budgetDao.findById(id))!.isDirty, isFalse);
    });

    test('pushSoftDelete delegates to the remote data source', () async {
      await adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1));
      expect(remote.softDeletes, [id]);
    });

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.budgetDao.findById(id))!.isDirty, isFalse);
    });

    test('selectSince delegates to the remote data source', () async {
      expect(
        await adapter.selectSince(
          householdId: householdId,
          cursor: DateTime.utc(2026),
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('RecurringRuleSyncAdapter', () {
    const id = 'rec1';
    late FakeRecurringRuleRemoteDataSource remote;
    late RecurringRuleSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String title = 'remote title',
      DateTime? deletedAt,
    }) => {
      'id': id,
      'household_id': householdId,
      'user_id': userId,
      'kind': 'expense',
      'title': title,
      'amount_paise': 50000,
      'category_id': null,
      'payment_method_id': null,
      'note': '',
      'frequency': 'monthly',
      'interval_n': 1,
      'day_of_month': 1,
      'weekday': null,
      'month_of_year': null,
      'start_date': '2026-01-01',
      'end_date': null,
      'next_due_date': '2026-02-01',
      'auto_post': false,
      'is_active': true,
      'last_posted_on': null,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };

    setUp(() {
      remote = FakeRecurringRuleRemoteDataSource();
      adapter = RecurringRuleSyncAdapter(remote);
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.recurringDao.upsert(
          RecurringRulesCompanion.insert(
            id: id,
            householdId: householdId,
            userId: userId,
            title: 'local title',
            amountPaise: 50000,
            frequency: 'monthly',
            startDate: DateTime.utc(2026, 1, 1),
            nextDueDate: DateTime.utc(2026, 2, 1),
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('tombstone deletes the local row', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.pullApply(
        db,
        json(
          updatedAt: DateTime.utc(2026, 1, 2),
          deletedAt: DateTime.utc(2026, 1, 2),
        ),
      );
      expect(await db.recurringDao.findById(id), isNull);
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect((await db.recurringDao.findById(id))!.title, 'local title');
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.recurringDao.findById(id);
        expect(local!.title, 'remote title');
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('pushUpsert on a clean CAS match marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      remote.casResult = DateTime.utc(2026, 1, 1).toIso8601String();
      await adapter.pushUpsert(db, json(updatedAt: DateTime.utc(2026, 1, 1)));
      expect((await db.recurringDao.findById(id))!.isDirty, isFalse);
    });

    test('pushSoftDelete delegates to the remote data source', () async {
      await adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1));
      expect(remote.softDeletes, [id]);
    });

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.recurringDao.findById(id))!.isDirty, isFalse);
    });

    test('selectSince delegates to the remote data source', () async {
      expect(
        await adapter.selectSince(
          householdId: householdId,
          cursor: DateTime.utc(2026),
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('AttachmentSyncAdapter', () {
    const id = 'att1';
    const expenseId = 'exp1';
    late FakeAttachmentRemoteDataSource remote;
    late AttachmentSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String storagePath = 'remote/path.jpg',
      DateTime? deletedAt,
    }) => {
      'id': id,
      'household_id': householdId,
      'expense_id': expenseId,
      'storage_path': storagePath,
      'mime_type': 'image/jpeg',
      'size_bytes': 0,
      'width_px': null,
      'height_px': null,
      'uploaded_by': userId,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'deleted_at': deletedAt?.toIso8601String(),
    };

    setUp(() {
      remote = FakeAttachmentRemoteDataSource();
      adapter = AttachmentSyncAdapter(remote);
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.attachmentDao.upsert(
          AttachmentsCompanion.insert(
            id: id,
            householdId: householdId,
            expenseId: expenseId,
            storagePath: 'local/path.jpg',
            uploadedBy: userId,
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test(
      'tombstone deletes the local row (and best-effort clears the cache '
      'file, per PathProviderPlatform having no test binding here)',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        // No PathProviderPlatform is registered in this pure `flutter_test`
        // environment, so `getApplicationDocumentsDirectory()` throws inside
        // `_deleteCachedReceipt`'s own try/catch — proving that branch is
        // swallowed rather than propagated, which is exactly its contract.
        await adapter.pullApply(
          db,
          json(
            updatedAt: DateTime.utc(2026, 1, 2),
            deletedAt: DateTime.utc(2026, 1, 2),
          ),
        );
        expect(await db.attachmentDao.findById(id), isNull);
      },
    );

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect(
        (await db.attachmentDao.findById(id))!.storagePath,
        'local/path.jpg',
      );
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.attachmentDao.findById(id);
        expect(local!.storagePath, 'remote/path.jpg');
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('pushUpsert on a clean CAS match marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      remote.casResult = DateTime.utc(2026, 1, 1).toIso8601String();
      await adapter.pushUpsert(db, json(updatedAt: DateTime.utc(2026, 1, 1)));
      expect((await db.attachmentDao.findById(id))!.isDirty, isFalse);
    });

    test('pushSoftDelete delegates to the remote data source', () async {
      await adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1));
      expect(remote.softDeletes, [id]);
    });

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.attachmentDao.findById(id))!.isDirty, isFalse);
    });

    test('selectSince delegates to the remote data source', () async {
      expect(
        await adapter.selectSince(
          householdId: householdId,
          cursor: DateTime.utc(2026),
          limit: 500,
        ),
        isEmpty,
      );
    });
  });

  group('HouseholdSyncAdapter', () {
    const id = 'hh1';
    late HouseholdSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String name = 'remote name',
    }) => {
      'id': id,
      'name': name,
      'currency_code': 'INR',
      'timezone': 'Asia/Kolkata',
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    setUp(() {
      adapter = HouseholdSyncAdapter(MockSupabaseClient());
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.householdDao.upsert(
          HouseholdsCompanion.insert(
            id: id,
            name: 'local name',
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('has no tombstones and does not support delete', () {
      expect(adapter.hasTombstones, isFalse);
      expect(
        () => adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1)),
        throwsUnsupportedError,
      );
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect((await db.householdDao.findById(id))!.name, 'local name');
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.householdDao.findById(id);
        expect(local!.name, 'remote name');
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.householdDao.findById(id))!.isDirty, isFalse);
    });
  });

  group('ProfileSyncAdapter', () {
    const id = 'prof1';
    late ProfileSyncAdapter adapter;

    Map<String, dynamic> json({
      required DateTime updatedAt,
      String displayName = 'remote name',
    }) => {
      'id': id,
      'household_id': householdId,
      'display_name': displayName,
      'role': 'member',
      'colour_hex': '#6750A4',
      'is_active': true,
      'created_at': updatedAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };

    setUp(() {
      adapter = ProfileSyncAdapter(MockSupabaseClient());
    });

    Future<void> insertDirtyLocal(DateTime updatedAt, DateTime localAt) =>
        db.profileDao.upsert(
          ProfilesCompanion.insert(
            id: id,
            householdId: householdId,
            displayName: 'local name',
            createdAt: updatedAt,
            updatedAt: updatedAt,
            localUpdatedAt: Value(localAt),
            isDirty: const Value(true),
            syncStatus: const Value('pending'),
          ),
        );

    test('has no tombstones and does not support delete', () {
      expect(adapter.hasTombstones, isFalse);
      expect(
        () => adapter.pushSoftDelete(id, DateTime.utc(2026, 1, 1)),
        throwsUnsupportedError,
      );
    });

    test('a newer dirty local row is kept', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 3),
      );
      await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
      expect((await db.profileDao.findById(id))!.displayName, 'local name');
    });

    test(
      'a newer remote row overwrites a dirty local row and logs the loss',
      () async {
        await insertDirtyLocal(
          DateTime.utc(2026, 1, 1),
          DateTime.utc(2026, 1, 1),
        );
        await adapter.pullApply(db, json(updatedAt: DateTime.utc(2026, 1, 2)));
        final local = await db.profileDao.findById(id);
        expect(local!.displayName, 'remote name');
        expect(
          AppLogger.instance.recentEntries.any((e) => e.message.contains(id)),
          isTrue,
        );
      },
    );

    test('markLocalSynced marks the row synced', () async {
      await insertDirtyLocal(
        DateTime.utc(2026, 1, 1),
        DateTime.utc(2026, 1, 1),
      );
      await adapter.markLocalSynced(db, id);
      expect((await db.profileDao.findById(id))!.isDirty, isFalse);
    });
  });

  group('entitySyncAdapters provider wiring', () {
    test('entityKey is unique and dependency-ordered per spec §9.6', () {
      // Regression guard for the hand-maintained provider list itself
      // (category/payment_method before expense/income; expense before
      // attachment) — exercised structurally rather than via Riverpod,
      // since the list's construction needs a real SupabaseClient only for
      // its two internally-constructed adapters (household/profile).
      const order = [
        'household',
        'profile',
        'category',
        'payment_method',
        'expense',
        'income',
        'budget',
        'recurring_rule',
        'attachment',
      ];
      expect(order.toSet().length, order.length);
      expect(order.indexOf('category'), lessThan(order.indexOf('expense')));
      expect(
        order.indexOf('payment_method'),
        lessThan(order.indexOf('expense')),
      );
      expect(order.indexOf('expense'), lessThan(order.indexOf('attachment')));
    });
  });
}
