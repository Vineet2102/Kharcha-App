import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../domain/models/expense_filter.dart';

part 'expense_list_preset_filter_controller.g.dart';

/// One-shot filter handoff from the Dashboard's per-member breakdown (spec
/// §11.4 card 3: "tapping a member filters the Expense List to them") to the
/// Expense List tab. `keepAlive` because it's set from outside the Expense
/// List's own widget tree and must still be there once that tab mounts;
/// [ExpenseListScreen] clears it immediately after reading it, so it never
/// re-applies on a later, unrelated visit to the tab.
@Riverpod(keepAlive: true)
class ExpenseListPresetFilterController
    extends _$ExpenseListPresetFilterController {
  @override
  ExpenseFilter? build() => null;

  void set(ExpenseFilter filter) => state = filter;

  void clear() => state = null;
}
