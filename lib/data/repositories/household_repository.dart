import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../domain/models/household.dart' as domain;
import '../local/mappers/household_mapper.dart';
import '../sync/sync_engine.dart';

part 'household_repository.g.dart';

const _uuid = Uuid();

/// Local-first read, admin-only write (spec §11.13, T-14.1: household name).
/// Every write goes to Drift + the outbox per the iron rule (§9.1) — RLS
/// (`hh_update`, admin-only) is the real enforcement; the Settings screen
/// only hides the edit control for members.
class HouseholdRepository {
  HouseholdRepository(this._db, this._triggerSync);

  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<domain.Household?> watch(String id) =>
      _db.householdDao.watchById(id).map((row) => row?.toDomain());

  Future<domain.Household?> findById(String id) async =>
      (await _db.householdDao.findById(id))?.toDomain();

  Future<void> updateName(String id, String name) async {
    final existing = await findById(id);
    if (existing == null) return;
    final updated = existing.copyWith(
      name: name,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.householdDao.upsert(updated.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'household',
        entityId: updated.id,
        op: 'upsert',
        payload: jsonEncode(updated.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
HouseholdRepository householdRepository(Ref ref) => HouseholdRepository(
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);

@Riverpod(keepAlive: true)
Stream<domain.Household?> household(Ref ref) =>
    ref.watch(householdRepositoryProvider).watch(AppConstants.seedHouseholdId);
