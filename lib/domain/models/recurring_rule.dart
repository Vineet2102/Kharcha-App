import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/money/money.dart';
import 'enums.dart';

part 'recurring_rule.freezed.dart';
part 'recurring_rule.g.dart';

@freezed
abstract class RecurringRule with _$RecurringRule {
  const factory RecurringRule({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    @JsonKey(name: 'user_id') required String userId,
    @Default(TxnKind.expense) TxnKind kind,
    required String title,
    @JsonKey(name: 'amount_paise') required int amountPaise,
    @JsonKey(name: 'category_id') String? categoryId,
    @JsonKey(name: 'payment_method_id') String? paymentMethodId,
    @Default('') String note,
    required RecurFrequency frequency,
    @JsonKey(name: 'interval_n') @Default(1) int intervalN,
    @JsonKey(name: 'day_of_month') int? dayOfMonth,
    int? weekday,
    @JsonKey(name: 'month_of_year') int? monthOfYear,
    @JsonKey(name: 'start_date') required DateTime startDate,
    @JsonKey(name: 'end_date') DateTime? endDate,
    @JsonKey(name: 'next_due_date') required DateTime nextDueDate,
    @JsonKey(name: 'auto_post') @Default(false) bool autoPost,
    @JsonKey(name: 'is_active') @Default(true) bool isActive,
    @JsonKey(name: 'last_posted_on') DateTime? lastPostedOn,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _RecurringRule;

  const RecurringRule._();

  Money get amount => Money(amountPaise);

  factory RecurringRule.fromJson(Map<String, Object?> json) =>
      _$RecurringRuleFromJson(json);
}
