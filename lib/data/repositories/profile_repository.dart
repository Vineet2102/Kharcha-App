import 'dart:async';
import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/profile.dart' as domain;
import '../local/mappers/profile_mapper.dart';
import '../remote/supabase_client_provider.dart';
import '../sync/sync_engine.dart';

part 'profile_repository.g.dart';

const _uuid = Uuid();

/// Caches the signed-in member's own `profiles` row locally (spec §11.1,
/// T-3.5), so the app can resolve "who am I / which household" offline from
/// the very next launch onward. Also owns the two Phase 14 write paths on
/// this table (spec §11.13 T-14.2/T-14.3) — every write goes to Drift + the
/// outbox per the iron rule (§9.1); RLS (`pr_update_self`: self, or admin
/// editing anyone) is the real enforcement, the UI only hides controls a
/// caller isn't allowed to use.
class ProfileRepository {
  ProfileRepository(this._client, this._db, this._triggerSync);

  final SupabaseClient _client;
  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<domain.Profile?> watch(String userId) =>
      _db.profileDao.watchById(userId).map((row) => row?.toDomain());

  Future<domain.Profile?> cached(String userId) async {
    final row = await _db.profileDao.findById(userId);
    return row?.toDomain();
  }

  /// Self-edit: display name (spec §11.13 "Profile" section).
  Future<void> updateDisplayName(String userId, String name) async {
    final existing = await cached(userId);
    if (existing == null) return;
    await _save(existing.copyWith(displayName: name));
  }

  /// Self-edit: avatar colour (spec §11.13 "Profile" section).
  Future<void> updateColourHex(String userId, String colourHex) async {
    final existing = await cached(userId);
    if (existing == null) return;
    await _save(existing.copyWith(colourHex: colourHex));
  }

  /// Admin-only: toggle another (or their own) member's `is_active` (spec
  /// §11.13 T-14.3). Callable on any household member's id — RLS's
  /// `pr_update_self` (`id = auth.uid() or is_admin()`) is what actually
  /// blocks a non-admin from using this on someone else.
  Future<void> setActive(String userId, bool isActive) async {
    final existing = await cached(userId);
    if (existing == null) return;
    await _save(existing.copyWith(isActive: isActive));
  }

  Future<void> _save(domain.Profile profile) async {
    final updated = profile.copyWith(updatedAt: DateTime.now().toUtc());
    await _db.profileDao.upsert(updated.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'profile',
        entityId: updated.id,
        op: 'upsert',
        payload: jsonEncode(updated.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }

  /// Best-effort remote refresh of the cached profile. Failures (offline,
  /// RLS, etc.) are logged and swallowed — the local cache stays the source
  /// of truth for the UI, per D5.
  ///
  /// Re-checks the session right before writing: this call is fired in the
  /// background (see [currentProfileProvider]) and can still be in flight
  /// when the user signs out mid-request. Without the check, the response
  /// would land after `AppDatabase.wipeAll()` and silently resurrect the
  /// profile row the sign-out wipe (T-3.6) just deleted.
  Future<void> refresh(String userId) async {
    try {
      final json = await _client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();
      if (_client.auth.currentSession?.user.id != userId) return;
      final profile = domain.Profile.fromJson(json);
      await _db.profileDao.upsert(profile.toCompanion());
    } catch (error, stackTrace) {
      AppLogger.instance.warn(
        'Profile refresh failed for $userId',
        error,
        stackTrace,
      );
    }
  }
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) => ProfileRepository(
  ref.watch(supabaseClientProvider),
  ref.watch(appDatabaseProvider),
  () => ref.read(syncEngineProvider).sync(),
);

/// Resolves offline from the Drift cache (T-3.5 acceptance) while kicking
/// off a background refresh whenever there's a signed-in user to refresh.
@Riverpod(keepAlive: true)
Stream<domain.Profile?> currentProfile(Ref ref) {
  final userId = ref.watch(currentSessionProvider)?.user.id;
  if (userId == null) return Stream.value(null);

  unawaited(ref.read(profileRepositoryProvider).refresh(userId));
  return ref.watch(profileRepositoryProvider).watch(userId);
}

/// Every member of the household — the "Paid by" selector (spec §11.2), the
/// Expense List's member filter/name chip (spec §11.3), and the Dashboard's
/// per-member breakdown (Phase 6).
@Riverpod(keepAlive: true)
Stream<List<domain.Profile>> householdProfiles(Ref ref) => ref
    .watch(appDatabaseProvider)
    .profileDao
    .watchAll(AppConstants.seedHouseholdId)
    .map((rows) => rows.map((r) => r.toDomain()).toList());

/// Looks up one member's display name/colour from the already-loaded
/// [householdProfilesProvider] list — avoids a second DB subscription per
/// expense row in the list/detail screens.
@riverpod
domain.Profile? profileById(Ref ref, String id) {
  final profiles = ref.watch(householdProfilesProvider).value ?? const [];
  for (final profile in profiles) {
    if (profile.id == id) return profile;
  }
  return null;
}
