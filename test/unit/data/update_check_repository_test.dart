import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/data/remote/app_release_remote_ds.dart';
import 'package:kharcha/data/repositories/update_check_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Overrides the network call so tests never touch Supabase — everything
/// else in [AppReleaseRemoteDataSource] is untouched (and untested here;
/// its query shape is a one-liner covered by manual/live verification per
/// this project's convention for thin remote data sources).
class _FakeAppReleaseRemoteDataSource extends AppReleaseRemoteDataSource {
  _FakeAppReleaseRemoteDataSource(this.response) : super(MockSupabaseClient());

  final Map<String, dynamic>? response;
  int callCount = 0;

  @override
  Future<Map<String, dynamic>?> fetchLatest(String platform) async {
    callCount++;
    return response;
  }
}

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Kharcha',
      packageName: 'com.panicker.kharcha',
      version: '1.2.0',
      buildNumber: '14',
      buildSignature: '',
    );
  });

  test('no release row at all is up to date', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = UpdateCheckRepository(_FakeAppReleaseRemoteDataSource(null));

    final result = await repo.checkForUpdates();

    expect(result, isA<UpToDate>());
  });

  test('release build_number <= current build is up to date', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = UpdateCheckRepository(
      _FakeAppReleaseRemoteDataSource({
        'platform': 'android',
        'version_name': '1.2.0',
        'build_number': 14,
        'min_supported': 1,
        'download_url': 'https://example.com/app.apk',
        'release_notes': '',
      }),
    );

    final result = await repo.checkForUpdates();

    expect(result, isA<UpToDate>());
  });

  test(
    'release build_number > current build is UpdateAvailable (spec §11.14)',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repo = UpdateCheckRepository(
        _FakeAppReleaseRemoteDataSource({
          'platform': 'android',
          'version_name': '1.3.0',
          'build_number': 20,
          'min_supported': 1,
          'download_url': 'https://example.com/app.apk',
          'release_notes': '',
        }),
      );

      final result = await repo.checkForUpdates();

      expect(result, isA<UpdateAvailable>());
      expect((result as UpdateAvailable).release.versionName, '1.3.0');
    },
  );

  test('min_supported > current build is Blocked, the emergency brake (spec '
      '§11.14)', () async {
    SharedPreferences.setMockInitialValues({});
    final repo = UpdateCheckRepository(
      _FakeAppReleaseRemoteDataSource({
        'platform': 'android',
        'version_name': '2.0.0',
        'build_number': 30,
        'min_supported': 20,
        'download_url': 'https://example.com/app.apk',
        'release_notes': '',
      }),
    );

    final result = await repo.checkForUpdates();

    expect(result, isA<Blocked>());
  });

  test('a dismissed banner for that build stays up to date', () async {
    SharedPreferences.setMockInitialValues({});
    final remote = _FakeAppReleaseRemoteDataSource({
      'platform': 'android',
      'version_name': '1.3.0',
      'build_number': 20,
      'min_supported': 1,
      'download_url': null,
      'release_notes': '',
    });
    final repo = UpdateCheckRepository(remote);

    final first = await repo.checkForUpdates(force: true);
    expect(first, isA<UpdateAvailable>());
    await repo.dismissBanner((first as UpdateAvailable).release.buildNumber);

    final second = await repo.checkForUpdates(force: true);
    expect(second, isA<UpToDate>());
  });

  test('a check under 24h old skips the network call unless forced', () async {
    SharedPreferences.setMockInitialValues({});
    final remote = _FakeAppReleaseRemoteDataSource({
      'platform': 'android',
      'version_name': '1.3.0',
      'build_number': 20,
      'min_supported': 1,
      'download_url': null,
      'release_notes': '',
    });
    final repo = UpdateCheckRepository(remote);

    await repo.checkForUpdates();
    expect(remote.callCount, 1);

    final throttled = await repo.checkForUpdates();
    expect(throttled, isA<UpToDate>());
    expect(remote.callCount, 1, reason: 'throttled — no second network call');

    final forced = await repo.checkForUpdates(force: true);
    expect(forced, isA<UpdateAvailable>());
    expect(remote.callCount, 2, reason: 'force bypasses the 24h throttle');
  });
}
