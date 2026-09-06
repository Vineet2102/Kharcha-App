import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:kharcha/core/constants/app_constants.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/settings/screens/settings_screen.dart';
import 'package:kharcha/routing/routes.dart';

import 'widget_test_helpers.dart';

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AppDatabase db;

  setUp(() async {
    PackageInfo.setMockInitialValues(
      appName: 'Kharcha',
      packageName: 'com.panicker.kharcha',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedHousehold(db, name: 'Panicker Family');
  });

  tearDown(() => db.close());

  Widget harness() {
    final router = GoRouter(
      initialLocation: AppRoutes.settings,
      routes: [
        GoRoute(
          path: AppRoutes.settings,
          builder: (context, state) => const SettingsScreen(),
        ),
        GoRoute(
          path: AppRoutes.members,
          builder: (context, state) =>
              const Scaffold(body: Text('Members screen')),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        supabaseClientProvider.overrideWithValue(client),
        appDatabaseProvider.overrideWithValue(db),
        syncEngineProvider.overrideWithValue(FakeSyncEngine()),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  /// The Settings list has ~20 tiles across 7 sections — taller than the
  /// default test viewport, so a plain `pumpWidget` leaves everything past
  /// roughly "Manage" outside `ListView`'s build cache extent and therefore
  /// absent from `find.text` (Sliver lists only build what's near the
  /// viewport, unlike a bare `Column`). Growing the viewport to fit
  /// everything sidesteps needing to scroll between assertions.
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
  }

  testWidgets('renders profile, household, and every section (T-14.1)', (
    tester,
  ) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    stubSignedInAs(auth, 'u1');

    await pumpSettings(tester);

    expect(find.text('Vineet'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Panicker Family'), findsOneWidget);
    expect(find.text('INR (₹)'), findsOneWidget);
    for (final section in [
      'Profile',
      'Household',
      'Manage',
      'Notifications',
      'Data',
      'About',
    ]) {
      // At least one, not exactly one: "Notifications" is both a section
      // header and that section's own (only) nav tile — both render the
      // literal text.
      expect(find.text(section), findsAtLeastNWidgets(1));
    }
    expect(find.text('Diagnostics'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('an admin can edit the household name (T-14.1)', (tester) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    stubSignedInAs(auth, 'u1');

    await pumpSettings(tester);

    await tester.tap(find.text('Panicker Family'));
    await tester.pumpAndSettle();

    // Two matches at this point, not one: the tile's own (static) subtitle
    // stays in the tree behind the now-open dialog, whose title is the same
    // literal text — scope to the dialog itself to check it actually opened.
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Household name'),
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'The Panickers');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final row = await db.householdDao.findById(AppConstants.seedHouseholdId);
    expect(row!.name, 'The Panickers');

    await disposeAndFlush(tester);
  });

  testWidgets('a member cannot edit the household name (T-14.1)', (
    tester,
  ) async {
    await seedProfile(
      db,
      id: 'u2',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Rupesh',
      isAdmin: false,
    );
    stubSignedInAs(auth, 'u2');

    await pumpSettings(tester);

    await tester.tap(find.text('Panicker Family'));
    await tester.pumpAndSettle();

    // The tile's own subtitle ("Household name") is always shown — a
    // member just gets a disabled `onTap`, so the real assertion is that no
    // edit dialog opened at all.
    expect(find.byType(AlertDialog), findsNothing);

    await disposeAndFlush(tester);
  });

  testWidgets('tapping Members navigates to the members screen (T-14.3)', (
    tester,
  ) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    stubSignedInAs(auth, 'u1');

    await pumpSettings(tester);

    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();

    expect(find.text('Members screen'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('Sync now shows a completion snackbar (T-14.4)', (tester) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    stubSignedInAs(auth, 'u1');

    await pumpSettings(tester);

    await tester.tap(find.text('Sync now'));
    await tester.pumpAndSettle();

    expect(find.text('Sync complete.'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets(
    'Clear local cache wipes the local database and re-syncs (T-14.4)',
    (tester) async {
      await seedProfile(
        db,
        id: 'u1',
        householdId: AppConstants.seedHouseholdId,
        displayName: 'Vineet',
        isAdmin: true,
      );
      stubSignedInAs(auth, 'u1');

      await pumpSettings(tester);

      await tester.tap(find.text('Clear local cache and re-download'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear & re-download'));
      await tester.pumpAndSettle();

      expect(find.text('Cache cleared and re-synced.'), findsOneWidget);
      expect(
        await db.householdDao.findById(AppConstants.seedHouseholdId),
        isNull,
      );

      await disposeAndFlush(tester);
    },
  );

  testWidgets('tapping the profile row opens the edit sheet (T-14.2)', (
    tester,
  ) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    stubSignedInAs(auth, 'u1');

    await pumpSettings(tester);

    await tester.tap(find.text('Vineet'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('Change password opens the change-password dialog (T-14.2)', (
    tester,
  ) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    stubSignedInAs(auth, 'u1');

    await pumpSettings(tester);

    await tester.tap(find.text('Change password'));
    await tester.pumpAndSettle();

    expect(find.text('New password'), findsOneWidget);
    expect(find.text('Confirm new password'), findsOneWidget);

    await disposeAndFlush(tester);
  });
}
