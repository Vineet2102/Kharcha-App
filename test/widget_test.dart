import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/app.dart';
import 'package:kharcha/data/remote/supabase_client_provider.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
    when(() => auth.onAuthStateChange)
        .thenAnswer((_) => Stream<AuthState>.empty());
  });

  testWidgets('signed-out user is redirected to /login (Gate 3, T-3.4)', (
    tester,
  ) async {
    when(() => auth.currentSession).thenReturn(null);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: const KharchaApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets(
    'signed-in user boots straight to the dashboard placeholder (Gate 2/3)',
    (tester) async {
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
          overrides: [supabaseClientProvider.overrideWithValue(client)],
          child: const KharchaApp(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsWidgets);
    },
  );
}
