import 'package:freezed_annotation/freezed_annotation.dart';

part 'household_invite.freezed.dart';
part 'household_invite.g.dart';

/// Mirrors one row of `public.household_invites` (spec §6.2, F-16) — read
/// live from Supabase, never mirrored into Drift: only one row (the current
/// active code) is ever fetched, and it must always reflect the server's
/// live state (expiry, use count) rather than a potentially-stale cache.
@freezed
abstract class HouseholdInvite with _$HouseholdInvite {
  const factory HouseholdInvite({
    required String id,
    required String code,
    @JsonKey(name: 'expires_at') required DateTime expiresAt,
    @JsonKey(name: 'max_uses') required int maxUses,
    @JsonKey(name: 'use_count') required int useCount,
  }) = _HouseholdInvite;

  factory HouseholdInvite.fromJson(Map<String, Object?> json) =>
      _$HouseholdInviteFromJson(json);
}
