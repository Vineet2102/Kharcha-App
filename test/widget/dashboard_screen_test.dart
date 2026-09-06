import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/constants/app_constants.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/repositories/update_check_repository.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/features/dashboard/screens/dashboard_screen.dart';

import 'widget_test_helpers.dart';

/// Spec §13's widget-layer row: "dashboard renders from a seeded DB, empty
/// states" (T-6.1..T-6.5).
class _UpToDate extends UpdateCheckController {
  @override
  UpdateCheckResult? build() => const UpToDate();
}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AppDatabase db;

  const userId = 'u1';
  final now = DateTime.now().toUtc();

  setUp(() async {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedHousehold(db);
    await seedProfile(db, id: userId, displayName: 'Vineet', isAdmin: true);
    stubSignedInAs(auth, userId);
  });

  tearDown(() => db.close());

  Widget harness() => ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      appDatabaseProvider.overrideWithValue(db),
      syncEngineProvider.overrideWithValue(FakeSyncEngine()),
      updateCheckControllerProvider.overrideWith(_UpToDate.new),
    ],
    child: const MaterialApp(home: DashboardScreen()),
  );

  testWidgets(
    'an empty household renders zeroed totals with no crash — no NaN, no '
    'divide-by-zero (T-6.5)',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.text('This month'), findsOneWidget);
      expect(find.text('Spent'), findsOneWidget);
      expect(find.text('₹0.00'), findsWidgets);
      expect(tester.takeException(), isNull);

      await disposeAndFlush(tester);
    },
  );

  testWidgets('renders the household summary and recent activity from a seeded '
      'expense', (tester) async {
    await db.categoryDao.upsert(
      CategoriesCompanion.insert(
        id: 'cat1',
        householdId: AppConstants.seedHouseholdId,
        name: 'Groceries',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: 'exp1',
        householdId: AppConstants.seedHouseholdId,
        userId: userId,
        amountPaise: 25000,
        categoryId: const Value('cat1'),
        note: const Value('Weekly shop'),
        spentAt: now,
        spentOn: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('₹250.00'), findsWidgets);
    expect(find.text('Groceries'), findsWidgets);
    expect(find.text('Weekly shop'), findsOneWidget);
    expect(find.text('Vineet'), findsWidgets);
    expect(tester.takeException(), isNull);

    await disposeAndFlush(tester);
  });
}
