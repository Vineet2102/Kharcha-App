import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_release.freezed.dart';
part 'app_release.g.dart';

/// Mirrors one row of `public.app_releases` (spec §6.8, §11.14) — read live
/// from Supabase, never mirrored into Drift: it's a tiny, admin-controlled
/// row, not household data, so there's nothing to keep working offline.
@freezed
abstract class AppRelease with _$AppRelease {
  const factory AppRelease({
    required String platform,
    @JsonKey(name: 'version_name') required String versionName,
    @JsonKey(name: 'build_number') required int buildNumber,
    @JsonKey(name: 'min_supported') @Default(1) int minSupported,
    @JsonKey(name: 'download_url') String? downloadUrl,
    @JsonKey(name: 'release_notes') @Default('') String releaseNotes,
  }) = _AppRelease;

  factory AppRelease.fromJson(Map<String, Object?> json) =>
      _$AppReleaseFromJson(json);
}
