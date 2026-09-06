import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/constants/app_constants.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/repositories/profile_repository.dart';
import 'package:kharcha/data/sync/sync_engine.dart';
import 'package:kharcha/domain/models/enums.dart';
import 'package:kharcha/domain/models/profile.dart' as domain;
import 'package:kharcha/features/expenses/screens/expense_detail_screen.dart';

import 'widget_test_helpers.dart';

/// Spec §13 Test 7: "A member's attempt to edit another member's expense is
/// rejected and shows a friendly message." Client-side, this never reaches a
/// rejected save attempt — `_canEdit` (owner-or-admin) swaps the whole form
/// for `_ReadOnlyExpenseView` before any edit control is even rendered (T-5.9);
/// the friendly-message half of the guarantee is RLS + `ErrorMapper` mapping
/// a `42501` denial to `PermissionFailure`'s default message (already
/// covered directly by `error_mapper_test.dart`, defence-in-depth for a path
/// that would only be reached if this client-side gate were ever bypassed).
void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AppDatabase db;

  const expenseId = 'exp1';
  const ownerId = 'owner1';
  const otherMemberId = 'other1';
  const adminId = 'admin1';

  setUp(() async {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedHousehold(db);
    await seedProfile(db, id: ownerId, displayName: 'Rupesh');
    await seedProfile(db, id: otherMemberId, displayName: 'Trupti');
    await seedProfile(db, id: adminId, displayName: 'Vineet', isAdmin: true);
    await db.expenseDao.upsert(
      ExpensesCompanion.insert(
        id: expenseId,
        householdId: AppConstants.seedHouseholdId,
        userId: ownerId,
        amountPaise: 25000,
        spentAt: DateTime.utc(2026, 9, 1),
        spentOn: DateTime.utc(2026, 9, 1),
        note: const Value('Groceries run'),
        createdAt: DateTime.utc(2026, 9, 1),
        updatedAt: DateTime.utc(2026, 9, 1),
      ),
    );
  });

  tearDown(() => db.close());

  domain.Profile profile(String id, String name, {bool isAdmin = false}) =>
      domain.Profile(
        id: id,
        householdId: AppConstants.seedHouseholdId,
        displayName: name,
        role: isAdmin ? MemberRole.admin : MemberRole.member,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );

  // `_ExpenseDetailScreenState._isAdmin` resolves `currentProfileProvider`
  // via `ref.read` (a one-shot snapshot, not `ref.watch`), so this test
  // overrides the provider directly with an already-resolved `Stream.value`
  // rather than relying on the real Drift-backed stream's resolution timing
  // racing against the widget's own rebuilds.
  Widget harness(domain.Profile viewer) => ProviderScope(
    overrides: [
      supabaseClientProvider.overrideWithValue(client),
      appDatabaseProvider.overrideWithValue(db),
      syncEngineProvider.overrideWithValue(FakeSyncEngine()),
      currentProfileProvider.overrideWith((ref) => Stream.value(viewer)),
    ],
    child: const MaterialApp(home: ExpenseDetailScreen(id: expenseId)),
  );

  testWidgets(
    'a member viewing another member\'s expense gets a read-only view — '
    'no amount field, no Save button',
    (tester) async {
      stubSignedInAs(auth, otherMemberId);

      await tester.pumpWidget(harness(profile(otherMemberId, 'Trupti')));
      await tester.pumpAndSettle();

      expect(find.text('₹250.00'), findsOneWidget);
      expect(find.text('Rupesh'), findsOneWidget);
      expect(find.text('Groceries run'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Save'), findsNothing);

      await disposeAndFlush(tester);
    },
  );

  testWidgets('the owner gets the full editable form', (tester) async {
    stubSignedInAs(auth, ownerId);

    await tester.pumpWidget(harness(profile(ownerId, 'Rupesh')));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await disposeAndFlush(tester);
  });

  testWidgets(
    'Add-expense form validation: an empty/invalid amount is rejected '
    'with an inline error and never reaches a save (spec §13 widget row)',
    (tester) async {
      stubSignedInAs(auth, ownerId);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            supabaseClientProvider.overrideWithValue(client),
            appDatabaseProvider.overrideWithValue(db),
            syncEngineProvider.overrideWithValue(FakeSyncEngine()),
            currentProfileProvider.overrideWith(
              (ref) => Stream.value(profile(ownerId, 'Rupesh')),
            ),
          ],
          child: const MaterialApp(home: ExpenseDetailScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid amount.'), findsOneWidget);
      // Only the pre-seeded `exp1` fixture from `setUp` exists — nothing new
      // was created by this rejected save attempt.
      expect(await db.select(db.expenses).get(), hasLength(1));

      await disposeAndFlush(tester);
    },
  );

  testWidgets('an admin gets the full editable form for anyone\'s expense', (
    tester,
  ) async {
    stubSignedInAs(auth, adminId);

    await tester.pumpWidget(harness(profile(adminId, 'Vineet', isAdmin: true)));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsWidgets);

    await disposeAndFlush(tester);
  });
}
