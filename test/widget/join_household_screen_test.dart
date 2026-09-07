import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/household_remote_ds.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/onboarding/screens/join_household_screen.dart';
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
      initialLocation: AppRoutes.onboardingJoin,
      routes: [
        GoRoute(
          path: AppRoutes.onboardingJoin,
          builder: (context, state) => const JoinHouseholdScreen(),
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

  testWidgets(
    'typing a lowercase, punctuated code auto-uppercases and inserts the '
    'dash',
    (tester) async {
      await pumpScreen(tester);

      // Deliberately not "ABCD-EFGH" — that's this field's own hint text,
      // which stays in the widget tree (opacity-animated, not removed) once
      // real text is entered, so asserting on it would find two matches.
      await tester.enterText(find.byType(TextField), 'wx.yz 12-34');
      await tester.pump();

      expect(find.text('WXYZ-1234'), findsOneWidget);

      await disposeAndFlush(tester);
    },
  );

  testWidgets('Join stays disabled until 8 significant characters are '
      'entered', (tester) async {
    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'ABCD');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.enterText(find.byType(TextField), 'ABCDEFGH');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );

    await disposeAndFlush(tester);
  });

  testWidgets('joining strips the dash before calling the RPC, then shows '
      "You've joined <name>, then Continue reaches the dashboard", (
    tester,
  ) async {
    when(
      () => remote.joinHousehold('ABCDEFGH'),
    ).thenAnswer((_) async => {'household_id': 'hh1', 'name': 'The Panickers'});

    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'ABCDEFGH');
    await tester.pump();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    verify(() => remote.joinHousehold('ABCDEFGH')).called(1);
    expect(find.text("You've joined The Panickers"), findsOneWidget);

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Dashboard screen'), findsOneWidget);

    await disposeAndFlush(tester);
  });

  testWidgets('invalid_invite maps to plain language inline', (tester) async {
    when(
      () => remote.joinHousehold(any()),
    ).thenThrow(PostgrestException(message: 'invalid_invite', code: 'P0001'));

    await pumpScreen(tester);

    await tester.enterText(find.byType(TextField), 'ABCDEFGH');
    await tester.pump();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();

    expect(
      find.text("That code isn't valid any more. Ask for a fresh one."),
      findsOneWidget,
    );

    await disposeAndFlush(tester);
  });
}
