import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:kharcha/app.dart';
import 'package:kharcha/core/config/app_config.dart';
import 'package:kharcha/core/constants/app_constants.dart';
import 'package:kharcha/core/network/connectivity_service.dart';
import 'package:kharcha/core/notifications/notification_service.dart';

/// Spec §13's one required end-to-end suite: "sign in → add expense →
/// appears in list → appears in dashboard total → toggle offline → add
/// another → back online → both sync." T-15.5.
///
/// **Must be run on a real Android device or emulator** (spec §13's own
/// acceptance line) against the real Supabase project, using
/// `config/dev.json` (see spec §5.6/§16) plus two extra `--dart-define`s for
/// a real household member's credentials, which are never committed:
///
/// ```bash
/// fvm flutter test integration_test/golden_path_test.dart \
///   --dart-define-from-file=config/dev.json \
///   --dart-define=TEST_USER_EMAIL=<a real member's email> \
///   --dart-define=TEST_USER_PASSWORD=<their password> \
///   --device-id=<id>
/// ```
///
/// The account used must be a disposable/test-tolerant member — this test
/// creates two real expenses in the real household and does not clean them
/// up, the same "left for a human to reconcile afterward" precedent every
/// live-device gate verification in docs/PROGRESS.md already follows.
///
/// The "toggle offline"/"back online" step does not flip the device's real
/// radio (no `adb`/native automation is wired into this suite — every
/// airplane-mode toggle in this project's history has been a manual `adb
/// shell svc wifi/data disable` step during a live gate verification, never
/// something the automated test itself drives). Instead this override the
/// app's [ConnectivityService] with a fake the test fully controls, so the
/// same real [SyncEngine]/[OutboxProcessor]/[PullService] machinery the app
/// ships with is exercised end to end, deterministically, without needing
/// out-of-band device control.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testEmail = String.fromEnvironment('TEST_USER_EMAIL');
  const testPassword = String.fromEnvironment('TEST_USER_PASSWORD');

  testWidgets('golden path: sign in, add expense offline and online, both '
      'sync (spec §13)', (tester) async {
    if (testEmail.isEmpty || testPassword.isEmpty) {
      fail(
        'TEST_USER_EMAIL/TEST_USER_PASSWORD were not provided via '
        '--dart-define — see this file\'s own doc comment for the full '
        'invocation. Skipping would silently hide this suite from CI '
        "(spec §14.1 doesn't run it), so it fails loudly instead.",
      );
    }
    AppConfig.assertValid();

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConstants.timeZoneName));
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    await NotificationService.instance.init();

    final connectivity = _FakeConnectivityService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityServiceProvider.overrideWithValue(connectivity),
        ],
        child: const KharchaApp(),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // --- sign in ---
    final emailField = find.byType(TextFormField).first;
    final passwordField = find.byType(TextFormField).last;
    await tester.enterText(emailField, testEmail);
    await tester.enterText(passwordField, testPassword);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.text('Dashboard'), findsOneWidget);

    // --- add an expense while online ---
    final beforeSpent = _spentText(tester);
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '111.00');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // --- appears in the Expense List ---
    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('₹111.00'), findsOneWidget);

    // --- appears in the Dashboard total ---
    await tester.tap(find.text('Dashboard'));
    await tester.pumpAndSettle();
    final afterOnlineSpent = _spentText(tester);
    expect(afterOnlineSpent, isNot(beforeSpent));

    // --- toggle offline (fake connectivity, real sync engine) ---
    connectivity.goOffline();
    await tester.pumpAndSettle();
    expect(find.textContaining('Offline'), findsOneWidget);

    // --- add another expense while offline ---
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '222.00');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle(const Duration(seconds: 3));
    expect(find.textContaining('changes waiting'), findsOneWidget);

    // --- back online — both sync ---
    connectivity.goOnline();
    await tester.pumpAndSettle(const Duration(seconds: 10));
    expect(find.textContaining('Offline'), findsNothing);

    await tester.tap(find.text('Expenses'));
    await tester.pumpAndSettle();
    expect(find.text('₹111.00'), findsOneWidget);
    expect(find.text('₹222.00'), findsOneWidget);
  });
}

String _spentText(WidgetTester tester) {
  final finder = find.descendant(
    of: find.ancestor(of: find.text('Spent'), matching: find.byType(Row)),
    matching: find.byType(Text),
  );
  return tester
      .widgetList<Text>(finder)
      .map((t) => t.data)
      .firstWhere((t) => t != 'Spent' && t != null)!;
}

class _FakeConnectivityService implements ConnectivityService {
  bool _online = true;
  final _controller = StreamController<bool>.broadcast();

  void goOffline() {
    _online = false;
    _controller.add(false);
  }

  void goOnline() {
    _online = true;
    _controller.add(true);
  }

  @override
  Future<bool> get isOnline async => _online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;
}
