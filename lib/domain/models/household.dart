import 'package:freezed_annotation/freezed_annotation.dart';

part 'household.freezed.dart';
part 'household.g.dart';

@freezed
abstract class Household with _$Household {
  const factory Household({
    required String id,
    required String name,
    @JsonKey(name: 'currency_code') @Default('INR') String currencyCode,
    @Default('Asia/Kolkata') String timezone,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
  }) = _Household;

  factory Household.fromJson(Map<String, Object?> json) =>
      _$HouseholdFromJson(json);
}
