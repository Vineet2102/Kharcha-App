import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';

part 'household_remote_ds.g.dart';

/// `households` is a single row per app (spec §1.4: single-tenant by
/// design) that essentially never changes after seeding, so it skips the
/// generic since-cursor paging machinery — a plain fetch-by-id is enough.
class HouseholdRemoteDataSource {
  const HouseholdRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> fetch(String id) =>
      _client.from('households').select().eq('id', id).maybeSingle();
}

@Riverpod(keepAlive: true)
HouseholdRemoteDataSource householdRemoteDataSource(Ref ref) =>
    HouseholdRemoteDataSource(ref.watch(supabaseClientProvider));
