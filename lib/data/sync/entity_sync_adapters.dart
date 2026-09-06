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

  /// Pushes one local edit, resolving a genuine cross-device conflict by
  /// timestamp rather than by push order (spec §13 Test 5 / D12 — see
  /// docs/DECISIONS.md, Gate 4 2026-09-05 fix). Fully owns the local row's
  /// post-push state: on success it stamps the row synced; on a conflict
  /// resolved in the remote's favour it overwrites the row (and logs the
  /// discarded edit) exactly as a routine pull would.
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload);

  Future<void> pushSoftDelete(String id, DateTime now);

  Future<void> markLocalSynced(AppDatabase db, String id);
}

/// The subset of a syncable row's sync-tracking columns [_pushUpsertWithCas]
/// needs to decide a push-time conflict.
class _LocalSyncMeta {
  const _LocalSyncMeta({
    required this.isDirty,
    required this.localUpdatedAt,
    required this.baseUpdatedAt,
  });

  final bool isDirty;
  final DateTime? localUpdatedAt;

  /// The server's raw ISO-8601 `updated_at` string as of the last confirmed
  /// sync — kept as a string, never a `DateTime`, so it round-trips through
  /// local storage and back into a push's CAS filter without ever losing
  /// the microsecond precision Postgres actually stores (see
  /// docs/DECISIONS.md, Gate 10 2026-09-05 fix).
  final String? baseUpdatedAt;
}

/// Thrown when a push loses a compare-and-swap race but the local edit is
/// genuinely newer than what's now on the server — a transient condition
/// (see [ErrorMapper]'s default classification), so [OutboxProcessor]
/// backs off and retries, by which point [updateBase] has already primed
/// the row's `baseUpdatedAt` with the value to CAS against next time.
class SyncConflictRetryException implements Exception {
  const SyncConflictRetryException(this.entityKey, this.id);

  final String entityKey;
  final String id;

  @override
  String toString() =>
      'SyncConflictRetryException: $entityKey/$id needs a retry after a '
      'push-time conflict (local edit is newer than the server\'s current '
      'value)';
}

/// Push-side counterpart to the pull-side D12 rule in [EntitySyncAdapter]'s
/// concrete `pullApply` methods (see docs/DECISIONS.md, Gate 4 2026-09-05
/// fix): a plain unconditional upsert lets whichever device happens to push
/// second silently clobber a genuinely newer edit made by another device.
/// This performs a compare-and-swap against the row's last known-good
/// server value (`baseUpdatedAt`) instead. A mismatch means someone else
/// moved the row since — resolved by comparing timestamps exactly like a
/// pull-time conflict (newest edit wins), never by push order:
///  - the local edit is genuinely newer → the row's base is refreshed to
///    the server's current value and a retry is requested (the outbox's
///    normal backoff drives the next attempt);
///  - otherwise the remote row wins → applied locally via [applyRemote]
///    (the same overwrite-and-log-the-loss path a routine pull uses).
Future<void> _pushUpsertWithCas({
  required String entityKey,
  required TableRemoteDataSource remote,
  required Map<String, dynamic> payload,
  required Future<_LocalSyncMeta?> Function() loadMeta,
  required Future<void> Function(String base) markSynced,
  required Future<void> Function(String base) updateBase,
  required Future<void> Function(Map<String, dynamic> remoteJson) applyRemote,
}) async {
  final id = payload['id'] as String;
  final meta = await loadMeta();
  final serverUpdatedAt = await remote.upsertIfBaseMatches(
    payload,
    meta?.baseUpdatedAt,
  );
  if (serverUpdatedAt != null) {
    // The server's own `touch_updated_at()` trigger may have advanced this
    // past the payload's claimed value (GREATEST(now(), incoming)) — always
    // trust what the server actually stored, never the payload, so the next
    // push's CAS check compares against reality (see docs/DECISIONS.md,
    // Gate 10).
    await markSynced(serverUpdatedAt);
    return;
  }

  final remoteJson = await remote.fetchById(id);
  if (remoteJson == null) {
    // The remote row vanished between the CAS attempt and this fetch —
    // nothing left to compare against, so just push it unconditionally
    // (the same path a brand-new row takes) and trust whatever the server
    // hands back this time, not the stale payload.
    final base = await remote.upsertIfBaseMatches(payload, null);
    await markSynced(base!);
    return;
  }

  final remoteUpdatedAt = _updatedAtOf(remoteJson);
  final localIsNewer =
      meta?.isDirty == true &&
      meta!.localUpdatedAt != null &&
      meta.localUpdatedAt!.isAfter(remoteUpdatedAt);
  if (localIsNewer) {
    await updateBase(remoteJson['updated_at'] as String);
    throw SyncConflictRetryException(entityKey, id);
  }

  if (meta?.isDirty == true) {
    _logConflictLoss(
      entityKey,
      id,
      localUpdatedAt: meta!.localUpdatedAt,
      remoteUpdatedAt: remoteUpdatedAt,
    );
  }
  await applyRemote(remoteJson);
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

/// [localUpdatedAt] is nullable defensively: it should always be set on a
/// dirty row (see `docs/DECISIONS.md`, Gate 10 — every mapper's
/// `toCompanion(dirty: true)` now stamps it), but a row dirtied by an
/// earlier build before that fix, or any future write path that forgets to,
/// must still log-and-move-on rather than crash the sync loop on a null
/// check.
void _logConflictLoss(
  String entityKey,
  String id, {
  required DateTime? localUpdatedAt,
  required DateTime remoteUpdatedAt,
}) {
  final editedAt = localUpdatedAt?.toIso8601String() ?? 'unknown time';
  AppLogger.instance.warn(
    'Sync conflict: local $entityKey/$id (edited $editedAt) was overwritten by a newer '
    'remote change ($remoteUpdatedAt) — the unpushed local edit was discarded (D12).',
  );
}

DateTime _updatedAtOf(Map<String, dynamic> json) =>
    DateTime.parse(json['updated_at'] as String).toUtc();

class HouseholdSyncAdapter extends EntitySyncAdapter {
  HouseholdSyncAdapter(SupabaseClient client)
    : _remote = HouseholdRemoteDataSource(client),
      // `households` has no `household_id` column (its own `id` IS the
      // household id), so [TableRemoteDataSource.selectSince] can't be used
      // for pull — but push (upsertIfBaseMatches/fetchById) filters by
      // `id`, which works for this table exactly like every other one
      // (spec §11.13 T-14: editing the household name, admin-only).
      _pushRemote = TableRemoteDataSource(client, 'households');

  final HouseholdRemoteDataSource _remote;
  final TableRemoteDataSource _pushRemote;

  @override
  String get entityKey => 'household';

  @override
  bool get supportsPush => true;

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
    final id = json['id'] as String;
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.householdDao.findById(id);
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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.householdDao.upsert(
      domain.Household.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _pushRemote,
        payload: payload,
        loadMeta: () async {
          final row = await db.householdDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.householdDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.householdDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      throw UnsupportedError('household has no delete path');

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.householdDao.markSynced(id);
}

class ProfileSyncAdapter extends EntitySyncAdapter {
  ProfileSyncAdapter(SupabaseClient client)
    : _remote = TableRemoteDataSource(client, 'profiles');

  final TableRemoteDataSource _remote;

  @override
  String get entityKey => 'profile';

  @override
  bool get supportsPush => true;

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
    final id = json['id'] as String;
    final remoteUpdatedAt = _updatedAtOf(json);
    final local = await db.profileDao.findById(id);
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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.profileDao.upsert(
      domain.Profile.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.profileDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.profileDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.profileDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      throw UnsupportedError('profile has no delete path');

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) =>
      db.profileDao.markSynced(id);
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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.categoryDao.upsert(
      domain.Category.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.categoryDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.categoryDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.categoryDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.paymentMethodDao.upsert(
      domain.PaymentMethod.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(
    AppDatabase db,
    Map<String, dynamic> payload,
  ) => _pushUpsertWithCas(
    entityKey: entityKey,
    remote: _remote,
    payload: payload,
    loadMeta: () async {
      final row = await db.paymentMethodDao.findById(payload['id'] as String);
      return row == null
          ? null
          : _LocalSyncMeta(
              isDirty: row.isDirty,
              localUpdatedAt: row.localUpdatedAt,
              baseUpdatedAt: row.baseUpdatedAt,
            );
    },
    markSynced: (base) =>
        db.paymentMethodDao.markSyncedWithBase(payload['id'] as String, base),
    updateBase: (base) =>
        db.paymentMethodDao.updateBaseUpdatedAt(payload['id'] as String, base),
    applyRemote: (json) => pullApply(db, json),
  );

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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.expenseDao.upsert(
      domain.Expense.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.expenseDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.expenseDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.expenseDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.incomeDao.upsert(
      domain.Income.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.incomeDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.incomeDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.incomeDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.budgetDao.upsert(
      domain.Budget.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.budgetDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.budgetDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.budgetDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.recurringDao.upsert(
      domain.RecurringRule.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.recurringDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.recurringDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.recurringDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

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
        localUpdatedAt: local!.localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
    await db.attachmentDao.upsert(
      domain.Attachment.fromJson(json)
          .toCompanion(baseUpdatedAt: json['updated_at'] as String),
    );
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      _pushUpsertWithCas(
        entityKey: entityKey,
        remote: _remote,
        payload: payload,
        loadMeta: () async {
          final row = await db.attachmentDao.findById(payload['id'] as String);
          return row == null
              ? null
              : _LocalSyncMeta(
                  isDirty: row.isDirty,
                  localUpdatedAt: row.localUpdatedAt,
                  baseUpdatedAt: row.baseUpdatedAt,
                );
        },
        markSynced: (base) =>
            db.attachmentDao.markSyncedWithBase(payload['id'] as String, base),
        updateBase: (base) =>
            db.attachmentDao.updateBaseUpdatedAt(payload['id'] as String, base),
        applyRemote: (json) => pullApply(db, json),
      );

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
  HouseholdSyncAdapter(ref.watch(supabaseClientProvider)),
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
