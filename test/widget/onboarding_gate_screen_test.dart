import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/onboarding/screens/onboarding_gate_screen.dart';
import 'package:kharcha/routing/routes.dart';

import 'widget_test_helpers.dart';

/// T-M2.6/T-M2.13: the household gate screen a confirmed, no-household
/// account lands on. No household RPC mocking needed — this screen is pure
/// navigation plus a sign-out escape hatch.
void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AppDatabase db;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    stubSignedInAs(auth, 'u1');
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  Future<void> pumpGate(WidgetTester tester) async {
    final router = GoRouter(
      initialLocation: AppRoutes.onboarding,
      routes: [
        GoRoute(
          path: AppRoutes.onboarding,
          builder: (context, state) => const OnboardingGateScreen(),
        ),
        GoRoute(
          path: AppRoutes.onboardingCreate,
          builder: (context, state) =>
              const Scaffold(body: Text('Create screen')),
        ),
        GoRoute(
          path: AppRoutes.onboardingJoin,
          builder: (context, state) =>
              const Scaffold(body: Text('Join screen')),
        ),
        GoRoute(
          path: AppRoutes.login,
          builder: (context, state) => const Scaffold(body: Text('Sign in')),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(FakeSyncEngine()),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows both cards, neither the default, and no "family" '
      'wording (D20)', (tester) async {
    await pumpGate(tester);

    expect(find.text('Create a household'), findsOneWidget);
    expect(find.text('Join a household'), findsOneWidget);
    expect(find.textContaining('family'), findsNothing);

    await disposeAndFlush(tester);
  });

  testWidgets('tapping Create a household navigates to /onboarding/create', (
    tester,
  ) async {
    await pumpGate(tester);

    await tester.tap(find.text('Create a household'));
    await tester.pumpAndSettle();

    expect(find.text('Create screen'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('tapping Join a household navigates to /onboarding/join', (
    tester,
  ) async {
    await pumpGate(tester);

    await tester.tap(find.text('Join a household'));
    await tester.pumpAndSettle();

    expect(find.text('Join screen'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('the sign-out icon confirms, then signs out and wipes local data '
      '(the router elsewhere is what actually redirects away — see '
      'widget_test.dart)', (tester) async {
    when(() => auth.signOut()).thenAnswer((_) async {});
    await seedHousehold(db);
    await seedProfile(db, id: 'u1', displayName: 'Vineet');
    await pumpGate(tester);

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();
    expect(
      find.text('This clears everything stored on this phone.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    verify(() => auth.signOut()).called(1);
    expect(await db.profileDao.findById('u1'), isNull);

    await disposeAndFlush(tester);
  });
}
