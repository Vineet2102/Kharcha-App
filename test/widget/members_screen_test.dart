import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/settings/screens/members_screen.dart';

import 'widget_test_helpers.dart';

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AppDatabase db;

  setUp(() async {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedHousehold(db);
    await seedProfile(
      db,
      id: 'u1',
      householdId: testHouseholdId,
      displayName: 'Vineet',
      isAdmin: true,
    );
    await seedProfile(
      db,
      id: 'u2',
      householdId: testHouseholdId,
      displayName: 'Rupesh',
      isAdmin: false,
    );
  });

  tearDown(() => db.close());

  Widget harness() => ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      appDatabaseProvider.overrideWithValue(db),
      syncEngineProvider.overrideWithValue(FakeSyncEngine()),
    ],
    child: const MaterialApp(home: MembersScreen()),
  );

  testWidgets(
    'an admin sees every member with a role and a toggle switch (T-14.3)',
    (tester) async {
      stubSignedInAs(auth, 'u1');

      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('Vineet'), findsOneWidget);
      expect(find.text('Admin'), findsOneWidget);
      expect(find.text('Rupesh'), findsOneWidget);
      expect(find.text('Member'), findsOneWidget);
      expect(find.byType(Switch), findsNWidgets(2));

      await disposeAndFlush(tester);
    },
  );

  testWidgets('an admin toggling a member off calls setActive (T-14.3)', (
    tester,
  ) async {
    stubSignedInAs(auth, 'u1');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final rupeshSwitch = find.descendant(
      of: find.ancestor(
        of: find.text('Rupesh'),
        matching: find.byType(ListTile),
      ),
      matching: find.byType(Switch),
    );
    await tester.tap(rupeshSwitch);
    await tester.pumpAndSettle();

    final row = await db.profileDao.findById('u2');
    expect(row!.isActive, isFalse);

    await disposeAndFlush(tester);
  });

  testWidgets('a member sees the same list read-only, no switches (T-14.3)', (
    tester,
  ) async {
    stubSignedInAs(auth, 'u2');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Vineet'), findsOneWidget);
    expect(find.text('Rupesh'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
    expect(find.text('Active'), findsNWidgets(2));

    await disposeAndFlush(tester);
  });
}
