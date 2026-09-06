import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'supabase_client_provider.dart';

part 'household_remote_ds.g.dart';

/// `households` is a single row per household (spec §1.4 for v1.0's single
/// household; v2.0 adds many) that changes rarely, so pulling it skips the
/// generic since-cursor paging machinery — a plain fetch-by-id is enough.
///
/// The RPC methods below (spec §6.9.2, T-M2.2) are every sanctioned way to
/// change household membership — each is `SECURITY DEFINER` server-side and
/// re-derives the caller from `auth.uid()`, so no caller-supplied user id is
/// ever trusted client-side either. Each is a single flat `rpc()` call with
/// no `.select()`/`.eq()` chaining, so — unlike the CAS push path in
/// `TableRemoteDataSource` — it stays a thin, one-line-per-method wrapper
/// whose query shape is covered by live verification, not a unit test; see
/// `HouseholdRepository`'s own tests for the Result-wrapping/error-mapping
/// logic that sits on top of this class.
class HouseholdRemoteDataSource {
  const HouseholdRemoteDataSource(this._client);

  final SupabaseClient _client;

  Future<Map<String, dynamic>?> fetch(String id) =>
      _client.from('households').select().eq('id', id).maybeSingle();

  Future<Map<String, dynamic>> createHousehold(String name) async =>
      await _client.rpc('create_household', params: {'p_name': name})
          as Map<String, dynamic>;

  Future<Map<String, dynamic>> joinHousehold(String code) async =>
      await _client.rpc('join_household', params: {'p_code': code})
          as Map<String, dynamic>;

  Future<void> leaveHousehold() => _client.rpc('leave_household');

  Future<void> setMemberRole(String userId, String role) => _client.rpc(
    'set_member_role',
    params: {'p_user': userId, 'p_role': role},
  );

  Future<void> setMemberActive(String userId, bool active) => _client.rpc(
    'set_member_active',
    params: {'p_user': userId, 'p_active': active},
  );

  Future<void> removeMember(String userId) =>
      _client.rpc('remove_member', params: {'p_user': userId});

  Future<String> createInvite({
    required int days,
    required int maxUses,
  }) async => await _client.rpc(
    'create_invite',
    params: {'p_days': days, 'p_max_uses': maxUses},
  ) as String;

  Future<void> revokeInvites() => _client.rpc('revoke_invites');

  Future<void> touchActivity() => _client.rpc('touch_activity');

  Future<void> deleteHousehold() => _client.rpc('delete_household');
}

@Riverpod(keepAlive: true)
HouseholdRemoteDataSource householdRemoteDataSource(Ref ref) =>
    HouseholdRemoteDataSource(ref.watch(supabaseClientProvider));
