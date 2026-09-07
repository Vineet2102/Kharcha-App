import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

@freezed
abstract class Profile with _$Profile {
  const factory Profile({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    @JsonKey(name: 'display_name') required String displayName,
    @Default(MemberRole.member) MemberRole role,
    @JsonKey(name: 'colour_hex') @Default('#6750A4') String colourHex,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'joined_at') DateTime? joinedAt,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Profile;

  const Profile._();

  bool get isAdmin => role == MemberRole.admin;

  factory Profile.fromJson(Map<String, Object?> json) =>
      _$ProfileFromJson(json);
}
