import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/constants/app_constants.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/sync/sync_engine.dart';

/// Shared mocktail/seeding helpers for Phase 14's per-screen widget tests —
/// pulled into one file once the 6th near-identical `MockSupabaseClient`
/// definition showed up, mirroring this project's own precedent for
/// hoisting a duplicated shape out once a second consumer needs it (see
/// `docs/DECISIONS.md`, `ColourSwatchPicker`).
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

/// A `SyncEngine` that never touches the network — every write-path
/// repository (`ProfileRepository`, `HouseholdRepository`, ...) calls
/// `syncEngineProvider.sync()` after every local write, and Settings'
/// "Sync now" calls it directly; overriding with this in a screen-level
/// widget test keeps the test deterministic instead of exercising the real
/// push/pull machinery against a mocked, unstubbed Supabase client.
class FakeSyncEngine extends Fake implements SyncEngine {
  @override
  Future<void> sync() async {}

  @override
  void start() {}

  @override
  void stop() {}
}

/// Stubs [auth] so [SupabaseClient.auth]'s session getter and auth-state
/// stream both agree a user with id [userId] is signed in — enough for
/// `currentSessionProvider`/`currentProfileProvider` to resolve without a
/// real Supabase connection (see `data/remote/supabase_client_provider.dart`).
void stubSignedInAs(MockGoTrueClient auth, String userId) {
  final session = Session(
    accessToken: 'token',
    tokenType: 'bearer',
    user: User(
      id: userId,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  );
  when(() => auth.currentSession).thenReturn(session);
  when(
    () => auth.onAuthStateChange,
  ).thenAnswer((_) => Stream<AuthState>.empty());
}

/// Defaults to [AppConstants.seedHouseholdId] — every household-scoped
/// provider (`householdProvider`, `householdProfilesProvider`, ...) queries
/// by that fixed id, not an arbitrary one, so seeding anything else leaves
/// those providers watching a household that doesn't exist.
Future<void> seedHousehold(
  AppDatabase db, {
  String id = AppConstants.seedHouseholdId,
  String name = 'Panicker Family',
}) {
  final now = DateTime.now().toUtc();
  return db.householdDao.upsert(
    HouseholdsCompanion.insert(id: id, name: name, createdAt: now, updatedAt: now),
  );
}

Future<void> seedProfile(
  AppDatabase db, {
  required String id,
  String householdId = AppConstants.seedHouseholdId,
  required String displayName,
  bool isAdmin = false,
  bool isActive = true,
  String colourHex = '#6750A4',
}) {
  final now = DateTime.now().toUtc();
  return db.profileDao.upsert(
    ProfilesCompanion.insert(
      id: id,
      householdId: householdId,
      displayName: displayName,
      role: Value(isAdmin ? 'admin' : 'member'),
      colourHex: Value(colourHex),
      isActive: Value(isActive),
      createdAt: now,
      updatedAt: now,
    ),
  );
}

/// Dashboard/Diagnostics-style screens keep live Drift stream queries open;
/// `pumpAndSettle` alone doesn't flush drift's zero-duration debounced-close
/// timer, so tearing down without this trips the test framework's "a Timer
/// is still pending" end-of-test check (same fix as `test/widget_test.dart`).
Future<void> disposeAndFlush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
