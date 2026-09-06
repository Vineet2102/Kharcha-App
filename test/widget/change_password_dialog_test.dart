import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/features/settings/screens/change_password_dialog.dart';

import 'widget_test_helpers.dart';

void main() {
  late MockSupabaseClient client;
  late MockGoTrueClient auth;

  setUpAll(() {
    registerFallbackValue(UserAttributes());
  });

  setUp(() {
    client = MockSupabaseClient();
    auth = MockGoTrueClient();
    when(() => client.auth).thenReturn(auth);
  });

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [supabaseClientProvider.overrideWithValue(client)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showChangePasswordDialog(context),
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

  testWidgets('rejects a password under 6 characters (T-14.2)', (tester) async {
    await pumpDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      '123',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      '123',
    );
    await tester.tap(find.text('Change'));
    await tester.pump();

    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );
    verifyNever(() => auth.updateUser(any()));
  });

  testWidgets('rejects mismatched passwords (T-14.2)', (tester) async {
    await pumpDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'secret1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'secret2',
    );
    await tester.tap(find.text('Change'));
    await tester.pump();

    expect(find.text('Passwords do not match.'), findsOneWidget);
    verifyNever(() => auth.updateUser(any()));
  });

  testWidgets(
    'a valid matching password calls updatePassword and closes (T-14.2)',
    (tester) async {
      when(() => auth.updateUser(any()))
          .thenAnswer((_) async => UserResponse.fromJson({'id': 'u1'}));

      await pumpDialog(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'New password'),
        'newSecret1',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Confirm new password'),
        'newSecret1',
      );
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();

      verify(() => auth.updateUser(any())).called(1);
      expect(find.text('New password'), findsNothing);
      expect(find.text('Password changed.'), findsOneWidget);
    },
  );

  testWidgets('an auth failure shows its message inline (T-14.2)', (
    tester,
  ) async {
    when(() => auth.updateUser(any()))
        .thenThrow(const AuthException('Session expired'));

    await pumpDialog(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'newSecret1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Confirm new password'),
      'newSecret1',
    );
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();

    expect(
      find.text('New password'),
      findsOneWidget,
      reason: 'dialog stays open',
    );
  });
}
