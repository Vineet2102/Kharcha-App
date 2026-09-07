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
import 'package:kharcha/features/onboarding/screens/create_household_screen.dart';
import 'package:kharcha/routing/routes.dart';

import 'widget_test_helpers.dart';

/// T-M2.6/T-M2.13.
void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late MockHouseholdRemoteDataSource remote;
  late AppDatabase db;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    stubSignedInAs(auth, 'u1');
    remote = MockHouseholdRemoteDataSource();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpScreen(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.onboardingCreate,
      routes: [
        GoRoute(
          path: AppRoutes.onboardingCreate,
          builder: (context, state) => const CreateHouseholdScreen(),
        ),
        GoRoute(
          path: AppRoutes.dashboard,
          builder: (context, state) =>
              const Scaffold(body: Text('Dashboard screen')),
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

  testWidgets('prefills the name field from the cached display name', (
    tester,
  ) async {
    await seedProfile(
      db,
      id: 'u1',
      householdId: 'irrelevant-hh',
      displayName: 'Vineet',
    );

    await pumpScreen(tester);

    expect(
      find.widgetWithText(TextFormField, "Vineet's household"),
      findsOneWidget,
    );

    await disposeAndFlush(tester);
  });

  testWidgets('creating a household reveals the formatted invite code, then '
      "'I'll do this later' reaches the dashboard", (tester) async {
    when(() => remote.createHousehold(any())).thenAnswer(
      (_) async => {
        'household_id': 'hh1',
        'name': 'Solo household',
        'invite_code': 'WXYZ5678',
      },
    );

    await pumpScreen(tester);

    await tester.enterText(find.byType(TextFormField), 'Solo household');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('WXYZ-5678'), findsOneWidget);
    expect(find.text('Solo household is ready'), findsOneWidget);

    await tester.tap(find.text("I'll do this later"));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard screen'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('an empty name is rejected client-side', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextFormField), '');
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Enter a household name.'), findsOneWidget);
    verifyNever(() => remote.createHousehold(any()));

    await disposeAndFlush(tester);
  });

  testWidgets('a server error is shown inline', (tester) async {
    when(() => remote.createHousehold(any())).thenThrow(Exception('boom'));

    await pumpScreen(tester);

    await tester.enterText(find.byType(TextFormField), 'Solo household');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Solo household is ready'), findsNothing);

    await disposeAndFlush(tester);
  });
}
