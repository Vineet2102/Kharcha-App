import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kharcha/data/remote/supabase_client_provider.dart';
import 'package:kharcha/data/repositories/update_check_repository.dart';
import 'package:kharcha/domain/models/app_release.dart';
import 'package:kharcha/features/dashboard/widgets/update_banner.dart';

import 'widget_test_helpers.dart';

/// Fixes [UpdateCheckController]'s state for a test instead of driving it
/// through a real `check()` call — [UpdateBanner] only cares about the
/// current state, and `checkForUpdates`'s own throttle/classification logic
/// already has direct coverage in `update_check_repository_test.dart`.
class _FixedUpdateCheckController extends UpdateCheckController {
  _FixedUpdateCheckController(this._initial);
  final UpdateCheckResult? _initial;

  @override
  UpdateCheckResult? build() => _initial;
}

void main() {
  const release = AppRelease(
    platform: 'android',
    versionName: '1.3.0',
    buildNumber: 20,
    minSupported: 1,
    downloadUrl: 'https://example.com/app.apk',
    releaseNotes: '',
  );

  testWidgets('renders nothing when there is no update (T-14.6)', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          updateCheckControllerProvider.overrideWith(
            () => _FixedUpdateCheckController(const UpToDate()),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: UpdateBanner())),
      ),
    );

    expect(find.byType(Card), findsNothing);
  });

  testWidgets(
    'shows the version and a Get it button when an update is available (T-14.6)',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            updateCheckControllerProvider.overrideWith(
              () => _FixedUpdateCheckController(const UpdateAvailable(release)),
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: UpdateBanner())),
        ),
      );

      expect(find.text('Version 1.3.0 is available'), findsOneWidget);
      expect(find.text('Get it'), findsOneWidget);
    },
  );

  testWidgets('dismissing the banner hides it (T-14.6)', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final client = MockSupabaseClient();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          supabaseClientProvider.overrideWithValue(client),
          updateCheckControllerProvider.overrideWith(
            () => _FixedUpdateCheckController(const UpdateAvailable(release)),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: UpdateBanner())),
      ),
    );
    expect(find.text('Version 1.3.0 is available'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(find.text('Version 1.3.0 is available'), findsNothing);
  });
}
