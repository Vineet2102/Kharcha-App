import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/money/money.dart';
import 'enums.dart';

part 'budget.freezed.dart';
part 'budget.g.dart';

@freezed
abstract class Budget with _$Budget {
  const factory Budget({
    required String id,
    @JsonKey(name: 'household_id') required String householdId,
    required BudgetScope scope,
    @JsonKey(name: 'user_id') String? userId,
    @JsonKey(name: 'category_id') String? categoryId,
    @JsonKey(name: 'amount_paise') required int amountPaise,
    @JsonKey(name: 'period_month') required DateTime periodMonth,
    @JsonKey(name: 'is_rollover') @Default(false) bool isRollover,
    @JsonKey(name: 'alert_threshold_pct') @Default(80) int alertThresholdPct,
    @JsonKey(name: 'created_by') required String createdBy,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    @JsonKey(name: 'updated_at') required DateTime updatedAt,
    @JsonKey(name: 'deleted_at') DateTime? deletedAt,
  }) = _Budget;

  const Budget._();

  Money get amount => Money(amountPaise);

  factory Budget.fromJson(Map<String, Object?> json) => _$BudgetFromJson(json);
}
