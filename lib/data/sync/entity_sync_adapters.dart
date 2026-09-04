import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/logging/app_logger.dart';
import '../local/mappers/attachment_mapper.dart';
import '../local/mappers/budget_mapper.dart';
import '../local/mappers/category_mapper.dart';
import '../local/mappers/expense_mapper.dart';
import '../local/mappers/household_mapper.dart';
import '../local/mappers/income_mapper.dart';
import '../local/mappers/payment_method_mapper.dart';
import '../local/mappers/profile_mapper.dart';
import '../local/mappers/recurring_rule_mapper.dart';
import '../remote/attachment_remote_ds.dart';
import '../remote/budget_remote_ds.dart';
import '../remote/category_remote_ds.dart';
import '../remote/expense_remote_ds.dart';
import '../remote/household_remote_ds.dart';
import '../remote/income_remote_ds.dart';
import '../remote/payment_method_remote_ds.dart';
import '../remote/recurring_rule_remote_ds.dart';
import '../remote/supabase_client_provider.dart';
import '../remote/table_remote_data_source.dart';
import '../../domain/models/attachment.dart' as domain;
import '../../domain/models/budget.dart' as domain;
import '../../domain/models/category.dart' as domain;
import '../../domain/models/expense.dart' as domain;
import '../../domain/models/household.dart' as domain;
import '../../domain/models/income.dart' as domain;
import '../../domain/models/payment_method.dart' as domain;
import '../../domain/models/profile.dart' as domain;
import '../../domain/models/recurring_rule.dart' as domain;

part 'entity_sync_adapters.g.dart';

/// Bridges one entity's raw remote JSON rows to its typed local Drift mirror
/// (spec §9.6). Every syncable table shares this shape; the 9 concrete
/// adapters below differ only in which remote data source, domain model,
/// and DAO they delegate to — see `docs/DECISIONS.md` for why these are
/// consolidated into one file rather than 9 near-duplicate ones.
abstract class EntitySyncAdapter {
  const EntitySyncAdapter();

  /// Matches `OutboxEntries.entity`.
  String get entityKey;

  /// False for `household`/`profile`: neither has any write path yet
  /// (Phase 14+), so they are pull-only.
  bool get supportsPush;

  /// False for `household`/`profile`: neither has a `deleted_at` column.
  bool get hasTombstones;

  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  });

  /// Applies one remote JSON row to the local mirror, honoring the D12
  /// conflict rule (spec §9.6 pullChanges()): a locally-dirty row newer than
  /// the incoming remote row is kept as-is (it will win on the next push);
  /// otherwise the remote row overwrites it, and if that discards an
  /// unpushed local edit, the loss is logged.
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json);

  Future<void> pushUpsert(Map<String, dynamic> payload);

  Future<void> pushSoftDelete(String id, DateTime now);

  Future<void> markLocalSynced(AppDatabase db, String id);
}

/// True when the local row must NOT be overwritten by the incoming remote
/// row — it is dirty (has an unpushed local edit) and that edit is strictly
/// newer than the remote row.
bool _localWins(
  bool isDirty,
  DateTime? localUpdatedAt,
  DateTime remoteUpdatedAt,
) =>
    isDirty &&
    localUpdatedAt != null &&
    localUpdatedAt.isAfter(remoteUpdatedAt);

void _logConflictLoss(
  String entityKey,
  String id, {
  required DateTime localUpdatedAt,
  required DateTime remoteUpdatedAt,
}) {
  AppLogger.instance.warn(
    'Sync conflict: local $entityKey/$id (edited $localUpdatedAt) was overwritten by a newer '
    'remote change ($remoteUpdatedAt) — the unpushed local edit was discarded (D12).',
  );
}

DateTime _updatedAtOf(Map<String, dynamic> json) =>
    DateTime.parse(json['updated_at'] as String).toUtc();

class HouseholdSyncAdapter extends EntitySyncAdapter {
  const HouseholdSyncAdapter(this._remote);

  final HouseholdRemoteDataSource _remote;

  @override
  String get entityKey => 'household';

  @override
  bool get supportsPush => false;

  @override
  bool get hasTombstones => false;

  /// Single row, fetched by id (`householdId` IS the household's own id) —
  /// there is exactly one household per app, so there's nothing to page.
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) async {
    final row = await _remote.fetch(householdId);
    return row == null ? const [] : [row];
  }

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    await db.householdDao.upsert(domain.Household.fromJson(json).toCompanion());
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      throw UnsupportedError('household is pull-only');

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      throw UnsupportedError('household is pull-only');

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) async {}
}

class ProfileSyncAdapter extends EntitySyncAdapter {
  ProfileSyncAdapter(SupabaseClient client)
    : _remote = TableRemoteDataSource(client, 'profiles');

  final TableRemoteDataSource _remote;

  @override
  String get entityKey => 'profile';

  @override
  bool get supportsPush => false;

  @override
  bool get hasTombstones => false;

  /// All household members, not just the signed-in one — needed so Phase 6
  /// can show a per-member breakdown for display names other than "me".
  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    await db.profileDao.upsert(domain.Profile.fromJson(json).toCompanion());
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      throw UnsupportedError('profile is pull-only');

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      throw UnsupportedError('profile is pull-only');

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) async {}
}

class CategorySyncAdapter extends EntitySyncAdapter {
  const CategorySyncAdapter(this._remote);

  final CategoryRemoteDataSource _remote;

  @override
  String get entityKey => 'category';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.categoryDao.hardDelete(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.categoryDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.categoryDao.upsert(domain.Category.fromJson(json).toCompanion());
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.categoryDao.markSynced(id);
}

class PaymentMethodSyncAdapter extends EntitySyncAdapter {
  const PaymentMethodSyncAdapter(this._remote);

  final PaymentMethodRemoteDataSource _remote;

  @override
  String get entityKey => 'payment_method';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.paymentMethodDao.hardDelete(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.paymentMethodDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.paymentMethodDao.upsert(
      domain.PaymentMethod.fromJson(json).toCompanion(),
    );
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.paymentMethodDao.markSynced(id);
}

class ExpenseSyncAdapter extends EntitySyncAdapter {
  const ExpenseSyncAdapter(this._remote);

  final ExpenseRemoteDataSource _remote;

  @override
  String get entityKey => 'expense';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.expenseDao.hardDelete(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.expenseDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.expenseDao.upsert(domain.Expense.fromJson(json).toCompanion());
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.expenseDao.markSynced(id);
}

class IncomeSyncAdapter extends EntitySyncAdapter {
  const IncomeSyncAdapter(this._remote);

  final IncomeRemoteDataSource _remote;

  @override
  String get entityKey => 'income';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.incomeDao.hardDelete(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.incomeDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.incomeDao.upsert(domain.Income.fromJson(json).toCompanion());
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.incomeDao.markSynced(id);
}

class BudgetSyncAdapter extends EntitySyncAdapter {
  const BudgetSyncAdapter(this._remote);

  final BudgetRemoteDataSource _remote;

  @override
  String get entityKey => 'budget';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.budgetDao.hardDelete(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.budgetDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.budgetDao.upsert(domain.Budget.fromJson(json).toCompanion());
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.budgetDao.markSynced(id);
}

class RecurringRuleSyncAdapter extends EntitySyncAdapter {
  const RecurringRuleSyncAdapter(this._remote);

  final RecurringRuleRemoteDataSource _remote;

  @override
  String get entityKey => 'recurring_rule';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.recurringDao.hardDelete(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.recurringDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.recurringDao.upsert(
      domain.RecurringRule.fromJson(json).toCompanion(),
    );
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.recurringDao.markSynced(id);
}

class AttachmentSyncAdapter extends EntitySyncAdapter {
  const AttachmentSyncAdapter(this._remote);

  final AttachmentRemoteDataSource _remote;

  @override
  String get entityKey => 'attachment';

  @override
  bool get supportsPush => true;

  @override
  bool get hasTombstones => true;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) => _remote.selectSince(
    householdId: householdId,
    cursor: cursor,
    limit: limit,
  );

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    final id = json['id'] as String;
    if (json['deleted_at'] != null) {
      await db.attachmentDao.hardDelete(id);
      await _deleteCachedReceipt(id);
      return;
    }
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.attachmentDao.findById(id);
    if (_localWins(
      local?.isDirty ?? false,
      local?.localUpdatedAt,
      remoteUpdatedAt,
    )) {
      return;
    }
    if (local?.isDirty ?? false) {
      _logConflictLoss(
        entityKey,
        id,
        localUpdatedAt: local!.localUpdatedAt!,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.attachmentDao.upsert(
      domain.Attachment.fromJson(json).toCompanion(),
    );
  }

  @override
  Future<void> pushUpsert(Map<String, dynamic> payload) =>
      _remote.upsert(payload);

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      _remote.softDelete(id, now);

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.attachmentDao.markSynced(id);

  static Future<void> _deleteCachedReceipt(String attachmentId) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File(
        p.join(dir.path, AppConstants.receiptsCacheDir, '$attachmentId.jpg'),
      );
      if (await file.exists()) await file.delete();
    } catch (error, stackTrace) {
      AppLogger.instance.warn(
        'Failed to delete cached receipt $attachmentId',
        error,
        stackTrace,
      );
    }
  }
}

/// Every syncable entity, in dependency order (spec §9.6 pushOutbox():
/// category/payment_method before expense/income; expense before
/// attachment). `household`/`profile` lead the list purely so the rest of
/// the app has fresh household/member data as early as possible in a cycle.
@Riverpod(keepAlive: true)
List<EntitySyncAdapter> entitySyncAdapters(Ref ref) => [
  HouseholdSyncAdapter(ref.watch(householdRemoteDataSourceProvider)),
  ProfileSyncAdapter(ref.watch(supabaseClientProvider)),
  CategorySyncAdapter(ref.watch(categoryRemoteDataSourceProvider)),
  PaymentMethodSyncAdapter(ref.watch(paymentMethodRemoteDataSourceProvider)),
  ExpenseSyncAdapter(ref.watch(expenseRemoteDataSourceProvider)),
  IncomeSyncAdapter(ref.watch(incomeRemoteDataSourceProvider)),
  BudgetSyncAdapter(ref.watch(budgetRemoteDataSourceProvider)),
  RecurringRuleSyncAdapter(ref.watch(recurringRuleRemoteDataSourceProvider)),
  AttachmentSyncAdapter(ref.watch(attachmentRemoteDataSourceProvider)),
];

@Riverpod(keepAlive: true)
Map<String, EntitySyncAdapter> entitySyncAdaptersByKey(Ref ref) => {
  for (final adapter in ref.watch(entitySyncAdaptersProvider))
    adapter.entityKey: adapter,
};
