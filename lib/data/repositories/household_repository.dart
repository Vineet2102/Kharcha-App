import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/household.dart' as domain;
import '../local/mappers/household_mapper.dart';
import '../remote/household_remote_ds.dart';
import '../sync/sync_engine.dart';
import 'profile_repository.dart';

part 'household_repository.g.dart';

const _uuid = Uuid();

/// Outcome of [HouseholdRepository.createHousehold] — the invite code is
/// only ever returned at creation time (spec F-15: shown once, large and
/// copyable); after that it's read from `household_invites` directly.
typedef CreateHouseholdOutcome = ({
  String householdId,
  String name,
  String inviteCode,
});

/// Outcome of [HouseholdRepository.joinHousehold].
typedef JoinHouseholdOutcome = ({String householdId, String name});

/// Local-first read, admin-only write (spec §11.13, T-14.1: household name)
/// for the existing household row, plus every membership-changing RPC added
/// in v2.0 (spec §6.9.2, F-15/F-16, T-M2.2). The RPCs are thin wrappers —
/// [HouseholdRemoteDataSource] does the actual network call; every method
/// here just catches whatever it throws and maps it through [ErrorMapper]
/// into a [Result], per this app's "never throw across the repository
/// boundary" rule (§9.7). None of these RPCs touch the outbox: unlike an
/// expense or a category, membership changes aren't safe to queue offline
/// and replay later — they need a live round trip to succeed at all.
class HouseholdRepository {
  HouseholdRepository(this._remote, this._db, this._triggerSync);

  final HouseholdRemoteDataSource _remote;
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

  /// Creates a new household with the caller as its sole admin, seeded with
  /// the 20 default categories and 6 payment methods, and mints its first
  /// invite code — all server-side in one transaction (spec F-15 "Create").
  Future<Result<CreateHouseholdOutcome, Failure>> createHousehold(
    String name,
  ) async {
    try {
      final json = await _remote.createHousehold(name);
      return Result.ok((
        householdId: json['household_id'] as String,
        name: json['name'] as String,
        inviteCode: json['invite_code'] as String,
      ));
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Joins an existing household by invite code (spec F-15 "Join").
  Future<Result<JoinHouseholdOutcome, Failure>> joinHousehold(
    String code,
  ) async {
    try {
      final json = await _remote.joinHousehold(code);
      return Result.ok((
        householdId: json['household_id'] as String,
        name: json['name'] as String,
      ));
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Leaves the caller's current household (spec F-16 "Leave household").
  /// The member's past transactions stay with the household by design
  /// (§1.5) — only their `profiles` row is detached.
  Future<Result<void, Failure>> leaveHousehold() async {
    try {
      await _remote.leaveHousehold();
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Admin-only: promote or demote another member (spec F-16 "Make admin /
  /// Make member").
  Future<Result<void, Failure>> setMemberRole(
    String userId,
    MemberRole role,
  ) async {
    try {
      await _remote.setMemberRole(userId, role.name);
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Admin-only: deactivate or reactivate a member (spec F-16, mirroring
  /// v1.0's T-14.3 now that it's a real RPC instead of a plain profile
  /// write — RLS no longer allows an admin to touch another member's row
  /// directly once membership fields are guarded).
  Future<Result<void, Failure>> setMemberActive(
    String userId,
    bool isActive,
  ) async {
    try {
      await _remote.setMemberActive(userId, isActive);
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Admin-only: remove a member from the household outright (spec F-16
  /// "Remove from household"). Their past transactions stay, same as
  /// leaving voluntarily.
  Future<Result<void, Failure>> removeMember(String userId) async {
    try {
      await _remote.removeMember(userId);
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Admin-only: mint a fresh invite code, revoking any currently-live one
  /// (spec F-16 "Regenerate" — only one live code exists at a time).
  Future<Result<String, Failure>> createInvite({
    int days = 30,
    int maxUses = 20,
  }) async {
    try {
      final code = await _remote.createInvite(days: days, maxUses: maxUses);
      return Result.ok(code);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Admin-only: revoke every live invite with nothing to replace it (spec
  /// F-16 "Revoke").
  Future<Result<void, Failure>> revokeInvites() async {
    try {
      await _remote.revokeInvites();
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Liveness ping (spec D21/F-17): `profiles.last_seen_at` and, if in a
  /// household, `households.last_active_at`. Called at most once per hour
  /// by the caller (T-M3.4) — this method itself has no throttle.
  Future<Result<void, Failure>> touchActivity() async {
    try {
      await _remote.touchActivity();
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }

  /// Admin-only, and only once they are the sole remaining member: deletes
  /// the household and every row cascading from it (spec F-16 "Delete
  /// household").
  Future<Result<void, Failure>> deleteHousehold() async {
    try {
      await _remote.deleteHousehold();
      return const Result.ok(null);
    } catch (error) {
      return Result.err(ErrorMapper.map(error));
    }
  }
}

@Riverpod(keepAlive: true)
HouseholdRepository householdRepository(Ref ref) => HouseholdRepository(
  ref.watch(householdRemoteDataSourceProvider),
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);

@Riverpod(keepAlive: true)
Stream<domain.Household?> household(Ref ref) {
  final householdId = ref.watch(currentHouseholdIdProvider);
  if (householdId == null) return Stream.value(null);
  return ref.watch(householdRepositoryProvider).watch(householdId);
}
