import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/app.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;
  late AppDatabase db;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.onAuthStateChange)
        .thenAnswer((_) => Stream<AuthState>.empty());
    // In-memory DB, not the real path-provider/background-isolate one: the
    // Dashboard (Phase 6) now issues Drift stream queries as soon as it
    // mounts, and the production `AppDatabase()` spins up a background
    // isolate whose keepalive timer outlives `pumpAndSettle` in a widget
    // test.
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() => db.close());

  testWidgets('signed-out user is redirected to /login (Gate 3, T-3.4)', (
    tester,
  ) async {
    when(() => auth.currentSession).thenReturn(null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const KharchaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Dashboard'), findsNothing);

    await _disposeAndFlush(tester);
  });

  testWidgets('signed-in user boots straight to the dashboard (Gate 2/3/6)', (
    tester,
  ) async {
    final user = User(
      id: 'u1',
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      createdAt: '2026-01-01T00:00:00Z',
    );
    final session = Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: user,
    );
    when(() => auth.currentSession).thenReturn(session);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const KharchaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsWidgets);

    await _disposeAndFlush(tester);
  });
}

/// The Dashboard (Phase 6) keeps several live Drift stream queries. Tearing
/// down the widget tree schedules drift's zero-duration debounced-close
/// timer (`StreamQueryStore.markAsClosed`); `pumpAndSettle` alone doesn't
/// flush a bare `Timer`, so without this the test framework's end-of-test
/// invariant check ("A Timer is still pending") fails.
Future<void> _disposeAndFlush(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(milliseconds: 1));
}
