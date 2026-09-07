import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/household_remote_ds.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/household/screens/household_management_screen.dart';
import 'package:kharcha/routing/routes.dart';

import 'widget_test_helpers.dart';

/// T-M2.9/T-M2.13. `HouseholdRemoteDataSource` is mocked throughout (same
/// convention as `household_repository_rpc_test.dart`) since every
/// membership action here is an RPC, never a local Drift write.
void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late MockHouseholdRemoteDataSource remote;
  late AppDatabase db;

  setUp(() async {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    remote = MockHouseholdRemoteDataSource();
    // No active invite by default — individual tests override this when the
    // invite section itself is under test.
    when(() => remote.fetchActiveInvite(any())).thenAnswer((_) async => null);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedHousehold(db, name: 'Panicker Family');
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.household,
      routes: [
        GoRoute(
          path: AppRoutes.household,
          builder: (context, state) => const HouseholdManagementScreen(),
        ),
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) =>
              const Scaffold(body: Text('Onboarding screen')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(FakeSyncEngine()),
          householdRemoteDataSourceProvider.overrideWithValue(remote),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('an admin sees the invite section; a member sees none of it', (
    tester,
  ) async {
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
    stubSignedInAs(auth, 'u1');
    await pumpScreen(tester);

    expect(find.text('No active invite code'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('a member sees no invite section, no overflow menu, and no '
      'delete option', (tester) async {
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
    await seedProfile(db, id: 'u2', displayName: 'Rupesh', isAdmin: false);
    stubSignedInAs(auth, 'u2');
    await pumpScreen(tester);

    expect(find.text('No active invite code'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text('Delete household'), findsNothing);
    expect(find.text('Leave household'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets(
    'the active invite renders formatted, with its expiry/use-cap meta line',
    (tester) async {
      when(() => remote.fetchActiveInvite(any())).thenAnswer(
        (_) async => {
          'id': 'inv1',
          'code': 'ABCD1234',
          'expires_at': DateTime.now()
              .toUtc()
              .add(const Duration(days: 10))
              .toIso8601String(),
          'max_uses': 20,
          'use_count': 3,
        },
      );
      await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
      stubSignedInAs(auth, 'u1');
      await pumpScreen(tester);

      expect(find.text('ABCD-1234'), findsOneWidget);
      expect(find.textContaining('used 3 of 20'), findsOneWidget);

      await disposeAndFlush(tester);
    },
  );

  testWidgets(
    'an admin sees an overflow menu on another member\'s row, not their own',
    (tester) async {
      await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
      await seedProfile(db, id: 'u2', displayName: 'Rupesh', isAdmin: false);
      stubSignedInAs(auth, 'u1');
      await pumpScreen(tester);

      expect(find.byType(PopupMenuButton<String>), findsOneWidget);
      expect(find.text('Vineet (you)'), findsOneWidget);
      expect(find.text('Rupesh'), findsOneWidget);

      await disposeAndFlush(tester);
    },
  );

  testWidgets('deactivating a member calls the RPC, not a direct profile '
      'write', (tester) async {
    when(() => remote.setMemberActive('u2', false)).thenAnswer((_) async {});
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
    await seedProfile(db, id: 'u2', displayName: 'Rupesh', isAdmin: false);
    stubSignedInAs(auth, 'u1');
    await pumpScreen(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deactivate'));
    await tester.pumpAndSettle();

    verify(() => remote.setMemberActive('u2', false)).called(1);

    await disposeAndFlush(tester);
  });

  testWidgets('removing a member confirms first, then calls removeMember', (
    tester,
  ) async {
    when(() => remote.removeMember('u2')).thenAnswer((_) async {});
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
    await seedProfile(db, id: 'u2', displayName: 'Rupesh', isAdmin: false);
    stubSignedInAs(auth, 'u1');
    await pumpScreen(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from household'));
    await tester.pumpAndSettle();

    expect(find.text('Remove Rupesh?'), findsOneWidget);
    verifyNever(() => remote.removeMember(any()));

    await tester.tap(find.widgetWithText(TextButton, 'Remove'));
    await tester.pumpAndSettle();

    verify(() => remote.removeMember('u2')).called(1);

    await disposeAndFlush(tester);
  });

  testWidgets('leaving confirms first, with the spec-exact consequence copy', (
    tester,
  ) async {
    when(() => remote.leaveHousehold()).thenAnswer((_) async {});
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: false);
    stubSignedInAs(auth, 'u1');
    await pumpScreen(tester);

    await tester.tap(find.text('Leave household'));
    await tester.pumpAndSettle();

    expect(find.text('Leave Panicker Family?'), findsOneWidget);
    verifyNever(() => remote.leaveHousehold());

    await tester.tap(find.widgetWithText(TextButton, 'Leave'));
    await tester.pumpAndSettle();

    verify(() => remote.leaveHousehold()).called(1);

    await disposeAndFlush(tester);
  });

  testWidgets('delete household is only offered to an admin who is the sole '
      'remaining member', (tester) async {
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
    await seedProfile(db, id: 'u2', displayName: 'Rupesh', isAdmin: false);
    stubSignedInAs(auth, 'u1');
    await pumpScreen(tester);

    expect(find.text('Delete household'), findsNothing);

    await disposeAndFlush(tester);
  });

  testWidgets(
    'deleting requires typing the exact household name before the RPC fires',
    (tester) async {
      when(() => remote.deleteHousehold()).thenAnswer((_) async {});
      await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
      stubSignedInAs(auth, 'u1');
      await pumpScreen(tester);

      expect(find.text('Delete household'), findsOneWidget);
      await tester.tap(find.text('Delete household'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Wrong name — must not delete.
      await tester.enterText(find.byType(TextField), 'Wrong Name');
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();
      verifyNever(() => remote.deleteHousehold());

      await disposeAndFlush(tester);
    },
  );

  testWidgets('typing the exact household name deletes it', (tester) async {
    when(() => remote.deleteHousehold()).thenAnswer((_) async {});
    await seedProfile(db, id: 'u1', displayName: 'Vineet', isAdmin: true);
    stubSignedInAs(auth, 'u1');
    await pumpScreen(tester);

    await tester.tap(find.text('Delete household'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Panicker Family');
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    verify(() => remote.deleteHousehold()).called(1);

    await disposeAndFlush(tester);
  });
}
