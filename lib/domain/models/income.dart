import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/money/money.dart';

part 'income.freezed.dart';
part 'income.g.dart';

@freezed
abstract class Income with _$Income {
  const factory Income({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'amount_paise') required int amountPaise,
    @JsonKey(name: 'category_id') String? categoryId,
    @JsonKey(name: 'received_at') required DateTime receivedAt,
    @JsonKey(name: 'received_on') required DateTime receivedOn,
    @Default('') String note,
    @Default('') String source,
    @JsonKey(name: 'recurring_rule_id') String? recurringRuleId,
    @JsonKey(name: 'occurrence_date') DateTime? occurrenceDate,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Income;

  const Income._();

  Money get amount => Money(amountPaise);

  factory Income.fromJson(Map<String, Object?> json) => _$IncomeFromJson(json);
}
