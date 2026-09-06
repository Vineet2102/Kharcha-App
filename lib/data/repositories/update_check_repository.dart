import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/app_release.dart';
import '../remote/app_release_remote_ds.dart';

part 'update_check_repository.g.dart';

/// Spec §11.14: no store, so the app must tell people a new build exists.
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpToDate extends UpdateCheckResult {
  const UpToDate();
}

/// `build_number > current build` — dismissible Dashboard banner.
class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.release);
  final AppRelease release;
}

/// `min_supported > current build` — the emergency brake: a non-dismissible
/// blocking dialog ("too old to sync safely").
class Blocked extends UpdateCheckResult {
  const Blocked(this.release);
  final AppRelease release;
}

const _lastCheckedAtKey = 'update_check_last_checked_at_ms';
const _throttle = Duration(hours: 24);

/// Reads the newest `app_releases` row for this platform (spec §11.14),
/// throttled to at most once per 24h unless [force]d — e.g. from Settings'
/// "Check for updates" button.
class UpdateCheckRepository {
  UpdateCheckRepository(this._remote);

  final AppReleaseRemoteDataSource _remote;

  Future<UpdateCheckResult> checkForUpdates({bool force = false}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!force) {
      final lastCheckedMs = prefs.getInt(_lastCheckedAtKey);
      if (lastCheckedMs != null) {
        final elapsed = DateTime.now().difference(
          DateTime.fromMillisecondsSinceEpoch(lastCheckedMs),
        );
        if (elapsed < _throttle) return const UpToDate();
      }
    }

    final platform = Platform.isIOS ? 'ios' : 'android';
    final json = await _remote.fetchLatest(platform);
    await prefs.setInt(_lastCheckedAtKey, DateTime.now().millisecondsSinceEpoch);
    if (json == null) return const UpToDate();

    final release = AppRelease.fromJson(json);
    final packageInfo = await PackageInfo.fromPlatform();
    final currentBuild = int.tryParse(packageInfo.buildNumber) ?? 0;

    if (release.minSupported > currentBuild) return Blocked(release);
    if (release.buildNumber > currentBuild) {
      final dismissedKey = 'update_banner_dismissed_${release.buildNumber}';
      if (prefs.getBool(dismissedKey) ?? false) return const UpToDate();
      return UpdateAvailable(release);
    }
    return const UpToDate();
  }

  Future<void> dismissBanner(int buildNumber) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('update_banner_dismissed_$buildNumber', true);
  }
}

@Riverpod(keepAlive: true)
UpdateCheckRepository updateCheckRepository(Ref ref) =>
    UpdateCheckRepository(ref.watch(appReleaseRemoteDataSourceProvider));

/// Latest check result, re-run at app start/resume (`app.dart`, mirroring
/// `notificationSchedulerProvider`'s wiring) and on-demand from Settings'
/// "Check for updates" button.
@Riverpod(keepAlive: true)
class UpdateCheckController extends _$UpdateCheckController {
  @override
  UpdateCheckResult? build() => null;

  Future<void> check({bool force = false}) async {
    state = await ref
        .read(updateCheckRepositoryProvider)
        .checkForUpdates(force: force);
  }

  Future<void> dismissBanner() async {
    final current = state;
    if (current is! UpdateAvailable) return;
    await ref
        .read(updateCheckRepositoryProvider)
        .dismissBanner(current.release.buildNumber);
    state = const UpToDate();
  }
}
