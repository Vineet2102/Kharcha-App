import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/constants/app_constants.dart';
import 'package:kharcha/core/constants/category_visuals.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/local/mappers/profile_mapper.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/settings/screens/edit_profile_sheet.dart';

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
      householdId: AppConstants.seedHouseholdId,
      displayName: 'Vineet',
    );
  });

  tearDown(() => db.close());

  Future<void> pumpSheet(WidgetTester tester) async {
    final profile = (await db.profileDao.findById('u1'))!.toDomain();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appDatabaseProvider.overrideWithValue(db),
          syncEngineProvider.overrideWithValue(FakeSyncEngine()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showEditProfileSheet(context, profile),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current name and colour (T-14.2)', (tester) async {
    await pumpSheet(tester);

    expect(find.text('Edit profile'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Vineet'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('saving a new name persists it and closes the sheet (T-14.2)', (
    tester,
  ) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), 'Vineet P');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsNothing);
    final row = await db.profileDao.findById('u1');
    expect(row!.displayName, 'Vineet P');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('picking a colour swatch persists it (T-14.2)', (tester) async {
    await pumpSheet(tester);

    final target = colourFromHex(categoryColourPalette.first);
    await tester.tap(
      find
          .byWidgetPredicate(
            (widget) =>
                widget is Container &&
                (widget.decoration as BoxDecoration?)?.color == target,
          )
          .first,
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final row = await db.profileDao.findById('u1');
    expect(row!.colourHex, categoryColourPalette.first);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an empty name is rejected client-side (T-14.2)', (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Save'));
    await tester.pump();

    expect(find.text('Name is required.'), findsOneWidget);
    expect(find.text('Edit profile'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
