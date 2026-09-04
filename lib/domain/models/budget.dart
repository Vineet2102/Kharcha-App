import 'package:freezed_annotation/freezed_annotation.dart';

import '../../core/money/money.dart';
import '../../core/time/app_time.dart';
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
    @JsonKey(name: 'period_month', fromJson: AppTime.parseDateOnly)
    required DateTime periodMonth,
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

/// Mirrors the DB's `budgets_scope_shape` check constraint (§6.5) exactly,
/// so an invalid combination is rejected client-side before it ever reaches
/// Postgres (T-8.1).
bool isValidBudgetScopeShape(
  BudgetScope scope,
  String? userId,
  String? categoryId,
) => switch (scope) {
  BudgetScope.household => userId == null && categoryId == null,
  BudgetScope.user => userId != null && categoryId == null,
  BudgetScope.category => userId == null && categoryId != null,
  BudgetScope.userCategory => userId != null && categoryId != null,
};
