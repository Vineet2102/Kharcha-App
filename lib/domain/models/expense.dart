import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/money/money.dart';

part 'expense.freezed.dart';
part 'expense.g.dart';

@freezed
abstract class Expense with _$Expense {
  const factory Expense({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    @JsonKey(name: 'user_id') required String userId,
    @JsonKey(name: 'amount_paise') required int amountPaise,
    @JsonKey(name: 'category_id') String? categoryId,
    @JsonKey(name: 'payment_method_id') String? paymentMethodId,
    @JsonKey(name: 'spent_at') required DateTime spentAt,
    @JsonKey(name: 'spent_on') required DateTime spentOn,
    @Default('') String note,
    @Default('') String merchant,
    @JsonKey(name: 'has_receipt') @Default(false) bool hasReceipt,
    @JsonKey(name: 'recurring_rule_id') String? recurringRuleId,
    @JsonKey(name: 'occurrence_date') DateTime? occurrenceDate,
    @JsonKey(name: 'created_by_device') String? createdByDevice,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Expense;

  const Expense._();

  Money get amount => Money(amountPaise);

  factory Expense.fromJson(Map<String, Object?> json) =>
      _$ExpenseFromJson(json);
}
