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
///
/// A second test (T-M2.13) extends the golden path to start from a brand-new
/// account instead of an existing member: sign up → verify email → create a
/// household → add an expense. It needs one more `--dart-define` — a real,
/// never-before-used, deliverable address — **and a human present to click
/// the real confirmation email** during its 5-minute polling window; there
/// is no way to automate clicking a link in a real inbox. This is the same
/// class of manual step T-M2.5's own verify-email screen was left
/// "unverified live" against:
///
/// ```bash
/// fvm flutter test integration_test/golden_path_test.dart \
///   --dart-define-from-file=config/dev.json \
///   --dart-define=TEST_USER_EMAIL=<a real member's email> \
///   --dart-define=TEST_USER_PASSWORD=<their password> \
///   --dart-define=TEST_SIGNUP_EMAIL=<a fresh, real, deliverable address> \
///   --device-id=<id>
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testEmail = String.fromEnvironment('TEST_USER_EMAIL');
  const testPassword = String.fromEnvironment('TEST_USER_PASSWORD');

  // Bootstrap once for the whole suite, not per-test: `Supabase.initialize`
  // throws if called a second time in the same process, and both tests in
  // this file need the identical tz/Supabase/notification setup.
  var bootstrapped = false;
  Future<void> ensureBootstrapped() async {
    if (bootstrapped) return;
    AppConfig.assertValid();
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation(AppConstants.timeZoneName));
    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      publishableKey: AppConfig.supabaseAnonKey,
    );
    await NotificationService.instance.init();
    bootstrapped = true;
  }

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
    await ensureBootstrapped();

    final connectivity = _FakeConnectivityService();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          connectivityServiceProvider.overrideWithValue(connectivity),
        ],
        child: const KharchaApp(),
      ),
    );

    // --- sign in ---
    // A generous polling wait, not a fixed pumpAndSettle duration: a real
    // device/emulator's cold start plus a real network round-trip to
    // Supabase (session check, `/login` redirect) is highly variable —
    // unlike a mocked widget test, there's no way to know in advance how
    // long the splash screen will show.
    await _pumpUntil(
      tester,
      () => find.byType(TextFormField).evaluate().length >= 2,
      timeout: const Duration(seconds: 60),
    );
    final emailField = find.byType(TextFormField).first;
    final passwordField = find.byType(TextFormField).last;
    await tester.enterText(emailField, testEmail);
    await tester.enterText(passwordField, testPassword);
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign in'));
    await _pumpUntil(
      tester,
      () => find.text('Dashboard').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );

    expect(find.text('Dashboard'), findsOneWidget);

    // --- add an expense while online ---
    final beforeSpent = _spentText(tester);
    await _addExpense(tester, amount: '111.00');
    await _pumpUntil(
      tester,
      () => find.text('Dashboard').evaluate().isNotEmpty,
    );

    // --- appears in the Expense List ---
    await _tap(tester, find.text('Expenses'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => find.text('₹111.00').evaluate().isNotEmpty);
    expect(find.text('₹111.00'), findsAtLeastNWidgets(1));

    // --- appears in the Dashboard total ---
    await _tap(tester, find.text('Dashboard'));
    await tester.pumpAndSettle();
    await _pumpUntil(
      tester,
      () => _spentText(tester) != beforeSpent,
      timeout: const Duration(seconds: 60),
    );
    final afterOnlineSpent = _spentText(tester);
    expect(afterOnlineSpent, isNot(beforeSpent));

    // The dashboard total updates from the local Drift write alone, before
    // the real push/pull this expense's own `_triggerSync()` kicked off has
    // necessarily finished — `SyncEngine.sync()` is single-flight, so
    // toggling offline and writing again too soon could have the *next*
    // trigger silently no-op against that still-in-flight cycle's lock.
    // Wait for the banner to leave "Syncing…" before moving on.
    await _pumpUntil(
      tester,
      () => find.text('Syncing…').evaluate().isEmpty,
      timeout: const Duration(seconds: 60),
    );

    // --- toggle offline (fake connectivity, real sync engine) ---
    // Going offline alone does not itself trigger a sync attempt — only an
    // offline→online transition does (`SyncEngine.start()`'s own trigger);
    // the banner only reflects "Offline" once *something* actually attempts
    // a cycle and finds no network. Adding the next expense provides that
    // trigger for real (`ExpenseRepository.create()`'s own post-write
    // `_triggerSync()`), so the "Offline — N changes waiting" banner is
    // checked after, not before.
    connectivity.goOffline();
    await tester.pumpAndSettle();

    // --- add another expense while offline ---
    await _addExpense(tester, amount: '222.00');
    await _pumpUntil(
      tester,
      () => find.textContaining('waiting').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 45),
    );
    expect(find.textContaining('waiting'), findsOneWidget);

    // --- back online — both sync ---
    connectivity.goOnline();
    await _pumpUntil(
      tester,
      () => find.textContaining('Offline').evaluate().isEmpty,
      timeout: const Duration(seconds: 60),
    );
    expect(find.textContaining('Offline'), findsNothing);

    await _tap(tester, find.text('Expenses'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => find.text('₹222.00').evaluate().isNotEmpty);
    expect(find.text('₹111.00'), findsAtLeastNWidgets(1));
    expect(find.text('₹222.00'), findsAtLeastNWidgets(1));
  });

  testWidgets('golden path from a brand-new account: sign up, verify email, create a '
      'household, add an expense (spec T-M2.13)', (tester) async {
    final signupEmail = const String.fromEnvironment('TEST_SIGNUP_EMAIL');
    const signupPassword = String.fromEnvironment(
      'TEST_SIGNUP_PASSWORD',
      defaultValue: 'GoldenPath123',
    );
    if (signupEmail.isEmpty) {
      fail(
        'TEST_SIGNUP_EMAIL was not provided via --dart-define. Must be a '
        'real, never-before-used, deliverable address — sign-up needs a '
        'human to click the real confirmation email during this test\'s '
        '5-minute polling window below (spec T-M1.8 requires email '
        'confirmation; there is no way to automate clicking a real inbox '
        'link). Run with e.g. '
        '--dart-define=TEST_SIGNUP_EMAIL=you+<a fresh timestamp>@example.com.',
      );
    }
    await ensureBootstrapped();

    await tester.pumpWidget(const ProviderScope(child: KharchaApp()));

    // --- sign up ---
    await _pumpUntil(
      tester,
      () => find.text('Sign in').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    await _tap(tester, find.text('New here? Create an account'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Golden Path Test');
    await tester.enterText(fields.at(1), signupEmail);
    await tester.enterText(fields.at(2), signupPassword);
    await tester.enterText(fields.at(3), signupPassword);
    await _tap(tester, find.widgetWithText(FilledButton, 'Create account'));
    await _pumpUntil(
      tester,
      () => find.text('Resend email').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );

    // --- verify email — needs a human to click the real link ---
    // VerifyEmailScreen polls `refreshSession()` every 5s on its own; this
    // just waits for that polling to land somewhere past it. Generous on
    // purpose: whoever runs this live needs time to notice the email.
    await _pumpUntil(
      tester,
      () =>
          find.text('Create a household').evaluate().isNotEmpty ||
          find.text('Dashboard').evaluate().isNotEmpty,
      timeout: const Duration(minutes: 5),
    );

    // --- household gate: create one ---
    if (find.text('Create a household').evaluate().isNotEmpty) {
      await _tap(tester, find.text('Create a household'));
      await tester.pumpAndSettle();
      // Entered explicitly rather than relying on the screen's own
      // prefill-from-cached-profile-name timing, which races the profile
      // row the sign-up trigger creates server-side.
      await tester.enterText(
        find.byType(TextFormField),
        'Golden Path Household',
      );
      await _tap(tester, find.widgetWithText(FilledButton, 'Continue'));
      await _pumpUntil(
        tester,
        () => find.text("I'll do this later").evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30),
      );
      await _tap(tester, find.text("I'll do this later"));
    }

    await _pumpUntil(
      tester,
      () => find.text('Dashboard').evaluate().isNotEmpty,
      timeout: const Duration(seconds: 60),
    );
    expect(find.text('Dashboard'), findsOneWidget);

    // --- the new household already has the 20 seeded categories/6 seeded
    // payment methods (spec F-15's own acceptance line) — adding an
    // expense exercises exactly that, reusing the same helper the other
    // test uses.
    await _addExpense(tester, amount: '50.00');
    await _tap(tester, find.text('Expenses'));
    await tester.pumpAndSettle();
    await _pumpUntil(tester, () => find.text('₹50.00').evaluate().isNotEmpty);
    expect(find.text('₹50.00'), findsAtLeastNWidgets(1));
  });
}

/// Opens Add Expense, fills the amount, picks the first available category
/// and payment method (both required by `_save()`'s own validation — see
/// `expense_detail_screen.dart`), and taps Save. Category/payment-method
/// chip counts vary with the real household's live data, so this scopes by
/// each section's private widget type (readable cross-library via
/// `runtimeType.toString()`) rather than an assumed flat chip index.
Future<void> _addExpense(WidgetTester tester, {required String amount}) async {
  await _tap(tester, find.byIcon(Icons.add));
  await _pumpUntil(tester, () => find.byType(TextField).evaluate().isNotEmpty);

  await tester.enterText(find.byType(TextField).first, amount);
  await tester.pumpAndSettle();

  final categorySection = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_CategoryChips',
  );
  final categoryChip = find.descendant(
    of: categorySection,
    matching: find.byType(ChoiceChip),
  );
  // Categories only appear once the household's very first post-sign-in
  // sync cycle has pulled `categories` down over a real network — a fresh
  // install (every run: `flutter test integration_test` reinstalls each
  // time) starts with a genuinely empty local cache, so this can take a
  // while on a slow/emulated connection.
  await _pumpUntil(
    tester,
    () => categoryChip.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 90),
  );
  await _tap(tester, categoryChip.first);

  final paymentMethodSection = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == '_PaymentMethodChips',
  );
  final paymentMethodChip = find.descendant(
    of: paymentMethodSection,
    matching: find.byType(ChoiceChip),
  );
  await _pumpUntil(
    tester,
    () => paymentMethodChip.evaluate().isNotEmpty,
    timeout: const Duration(seconds: 90),
  );
  await _tap(tester, paymentMethodChip.first);

  // The Save button sits below several sections (date, note, merchant,
  // possibly an admin-only "Paid by" picker) that don't all fit on a real
  // device screen at once — scroll it into view rather than assuming it's
  // already visible.
  await tester.dragUntilVisible(
    find.text('Save'),
    find.byType(ListView),
    const Offset(0, -300),
  );
  await _tap(tester, find.text('Save'));
  // A real push to Supabase (when online) or an outbox enqueue (when
  // offline) — either way, wait for the screen to actually pop rather than
  // a fixed delay.
  await _pumpUntil(
    tester,
    () => find.byType(TextField).evaluate().isEmpty,
    timeout: const Duration(seconds: 15),
  );
}

/// A plain `tester.tap()` occasionally hits a transient "no View ancestor"
/// framework error immediately after a live provider-driven rebuild (seen
/// in practice against the real Supabase project, where a Drift stream can
/// re-emit — and rebuild the tapped element's subtree — in the same frame
/// window as the tap). Settling first and retrying absorbs that without
/// weakening what the test actually proves (every retry still taps the same
/// real widget; nothing here is mocked away).
Future<void> _tap(WidgetTester tester, Finder finder) async {
  for (var attempt = 1; attempt <= 3; attempt++) {
    await tester.pumpAndSettle();
    try {
      await tester.tap(finder);
      return;
    } catch (_) {
      // If the target has already disappeared from the tree, the tap most
      // likely landed before the framework-internal error fired (e.g. the
      // screen already navigated away) — retrying here would risk a
      // double-tap (a second real Save, a duplicate expense). Nothing left
      // to retry against, so treat it as done rather than blindly retrying.
      if (finder.evaluate().isEmpty) return;
      if (attempt == 3) rethrow;
      await tester.pump(const Duration(milliseconds: 300));
    }
  }
}

/// Polls with real pumps (never a fixed sleep) until [condition] is true or
/// [timeout] elapses — the only reliable way to wait for a real network
/// round-trip / real device timing in an integration test.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out after $timeout waiting for a condition to become true.');
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pumpAndSettle();
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
