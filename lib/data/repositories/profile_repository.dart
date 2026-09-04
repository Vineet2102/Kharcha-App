import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/logging/app_logger.dart';
import '../../domain/models/profile.dart' as domain;
import '../local/mappers/profile_mapper.dart';
import '../remote/supabase_client_provider.dart';

part 'profile_repository.g.dart';

/// Caches the signed-in member's own `profiles` row locally (spec §11.1,
/// T-3.5), so the app can resolve "who am I / which household" offline from
/// the very next launch onward.
class ProfileRepository {
  ProfileRepository(this._client, this._db);

  final SupabaseClient _client;
  final AppDatabase _db;

  Stream<domain.Profile?> watch(String userId) =>
      _db.profileDao.watchById(userId).map((row) => row?.toDomain());

  Future<domain.Profile?> cached(String userId) async {
    final row = await _db.profileDao.findById(userId);
    return row?.toDomain();
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
      final json = await _client.from('profiles').select().eq('id', userId).single();
      if (_client.auth.currentSession?.user.id != userId) return;
      final profile = domain.Profile.fromJson(json);
      await _db.profileDao.upsert(profile.toCompanion());
    } catch (error, stackTrace) {
      AppLogger.instance.warn('Profile refresh failed for $userId', error, stackTrace);
    }
  }
}

@Riverpod(keepAlive: true)
ProfileRepository profileRepository(Ref ref) =>
    ProfileRepository(ref.watch(supabaseClientProvider), ref.watch(appDatabaseProvider));

/// Resolves offline from the Drift cache (T-3.5 acceptance) while kicking
/// off a background refresh whenever there's a signed-in user to refresh.
@Riverpod(keepAlive: true)
Stream<domain.Profile?> currentProfile(Ref ref) {
  final userId = ref.watch(currentSessionProvider)?.user.id;
  if (userId == null) return Stream.value(null);

  unawaited(ref.read(profileRepositoryProvider).refresh(userId));
  return ref.watch(profileRepositoryProvider).watch(userId);
}
