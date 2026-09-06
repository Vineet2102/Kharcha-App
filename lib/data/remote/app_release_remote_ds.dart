import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';

part 'app_release_remote_ds.g.dart';

/// `app_releases` (spec §6.8, §11.14) — the newest row for a platform, read
/// live on demand rather than mirrored into Drift (see
/// `domain/models/app_release.dart`).
class AppReleaseRemoteDataSource {
  const AppReleaseRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> fetchLatest(String platform) {
    return _client
        .from('app_releases')
        .select()
        .eq('platform', platform)
        .order('build_number', ascending: false)
        .limit(1)
        .maybeSingle();
  }
}

@Riverpod(keepAlive: true)
AppReleaseRemoteDataSource appReleaseRemoteDataSource(Ref ref) =>
    AppReleaseRemoteDataSource(ref.watch(supabaseClientProvider));
