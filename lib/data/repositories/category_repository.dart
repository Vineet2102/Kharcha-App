import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../domain/models/category.dart' as domain;
import '../../domain/models/enums.dart';
import '../local/mappers/category_mapper.dart';
import '../sync/sync_engine.dart';

part 'category_repository.g.dart';

const _uuid = Uuid();

/// Local-first read, admin-only write (spec §11.5, T-5.1). Every write goes
/// to Drift + the outbox per the iron rule (§9.1) — RLS (`cat_write`,
/// admin-only) is the real enforcement; screens only hide the controls for
/// members so a blocked write is never even attempted from the UI.
class CategoryRepository {
  CategoryRepository(this._db, this._triggerSync);

  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<List<domain.Category>> watchAll(String householdId) => _db
      .categoryDao
      .watchAll(householdId)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Future<domain.Category?> findById(String id) async =>
      (await _db.categoryDao.findById(id))?.toDomain();

  Future<void> create({
    required String householdId,
    required String name,
    required CategoryKind kind,
    required String iconKey,
    required String colourHex,
    int sortOrder = 100,
  }) {
    final now = DateTime.now().toUtc();
    return _save(
      domain.Category(
        id: _uuid.v4(),
        householdId: householdId,
        name: name,
        kind: kind,
        iconKey: iconKey,
        colourHex: colourHex,
        sortOrder: sortOrder,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> update(domain.Category category) =>
      _save(category.copyWith(updatedAt: DateTime.now().toUtc()));

  Future<void> setArchived(String id, bool archived) async {
    final existing = await findById(id);
    if (existing == null) return;
    await update(existing.copyWith(isArchived: archived));
  }

  /// Persists new `sort_order` values after a drag-to-reorder, spaced by 10
  /// so a future manual insert doesn't require renumbering everything.
  Future<void> reorder(List<domain.Category> reordered) async {
    for (var i = 0; i < reordered.length; i++) {
      await _save(
        reordered[i].copyWith(
          sortOrder: (i + 1) * 10,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// Soft-deletes, unless the category is still used by a non-deleted
  /// expense (spec §11.5) — callers should offer "Archive instead" on
  /// [ValidationFailure].
  Future<Result<void, Failure>> delete(String id) async {
    final usage = await _db.expenseDao.countByCategory(id);
    if (usage > 0) {
      return const Result.err(
        ValidationFailure(
          'This category is used by existing expenses — archive it instead.',
        ),
      );
    }
    final existing = await findById(id);
    if (existing == null) return const Result.ok(null);
    final now = DateTime.now().toUtc();
    await _db.categoryDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'category',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    _triggerSync();
    return const Result.ok(null);
  }

  Future<void> _save(domain.Category category) async {
    await _db.categoryDao.upsert(category.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'category',
        entityId: category.id,
        op: 'upsert',
        payload: jsonEncode(category.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
CategoryRepository categoryRepository(Ref ref) => CategoryRepository(
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);

/// All categories (incl. archived — callers filter as needed), for the
/// management screen and every expense-form category picker.
@Riverpod(keepAlive: true)
Stream<List<domain.Category>> categories(Ref ref) => ref
    .watch(categoryRepositoryProvider)
    .watchAll(AppConstants.seedHouseholdId);
