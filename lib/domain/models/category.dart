import 'package:freezed_annotation/freezed_annotation.dart';

import 'enums.dart';

part 'category.freezed.dart';
part 'category.g.dart';

@freezed
abstract class Category with _$Category {
  const factory Category({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    required String name,
    @Default(CategoryKind.expense) CategoryKind kind,
    @JsonKey(name: 'icon_key') @Default('category') String iconKey,
    @JsonKey(name: 'colour_hex') @Default('#607D8B') String colourHex,
    @JsonKey(name: 'sort_order') @Default(100) int sortOrder,
    @JsonKey(name: 'is_archived') @Default(false) bool isArchived,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Category;

  factory Category.fromJson(Map<String, Object?> json) =>
      _$CategoryFromJson(json);
}
