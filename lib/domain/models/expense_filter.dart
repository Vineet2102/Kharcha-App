import 'package:freezed_annotation/freezed_annotation.dart';

part 'expense_filter.freezed.dart';

/// Combinable filters for the Expense List (spec §11.3). `startDate`/
/// `endDate` are inclusive IST calendar dates (see `AppTime.calendarDate`,
/// UTC-flagged), compared directly against `Expenses.spentOn`.
@freezed
abstract class ExpenseFilter with _$ExpenseFilter {
  const factory ExpenseFilter({
    DateTime? startDate,
    DateTime? endDate,
    @Default([]) List<String> memberIds,
    @Default([]) List<String> categoryIds,
    @Default([]) List<String> paymentMethodIds,
    int? minAmountPaise,
    int? maxAmountPaise,
    @Default(false) bool onlyWithReceipts,
    @Default('') String searchText,
  }) = _ExpenseFilter;

  const ExpenseFilter._();

  bool get hasActiveFilters =>
      memberIds.isNotEmpty ||
      categoryIds.isNotEmpty ||
      paymentMethodIds.isNotEmpty ||
      minAmountPaise != null ||
      maxAmountPaise != null ||
      onlyWithReceipts ||
      searchText.trim().isNotEmpty;
}
