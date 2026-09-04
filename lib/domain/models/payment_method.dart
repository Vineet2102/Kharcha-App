import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'payment_method.freezed.dart';
part 'payment_method.g.dart';

@freezed
abstract class PaymentMethod with _$PaymentMethod {
  const factory PaymentMethod({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    required String name,
    @Default(PayMethodType.other) PayMethodType type,
    @JsonKey(name: 'is_archived') @Default(false) bool isArchived,
    @JsonKey(name: 'sort_order') @Default(100) int sortOrder,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _PaymentMethod;

  factory PaymentMethod.fromJson(Map<String, Object?> json) => _$PaymentMethodFromJson(json);
}
