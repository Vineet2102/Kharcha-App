import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/time/app_time.dart';

part 'selected_month_controller.g.dart';

/// The month shown on the Dashboard app bar (spec §11.4, T-6.2). State is
/// always a month-start value (see [AppTime.monthStart]). `keepAlive` so the
/// choice survives switching tabs — and, once Analytics (Phase 11) exists,
/// so the two screens can share it.
@Riverpod(keepAlive: true)
class SelectedMonthController extends _$SelectedMonthController {
  @override
  DateTime build() => AppTime.monthStart(DateTime.now().toUtc());

  void previousMonth() => state = AppTime.monthAfter(state, -1);

  /// No-ops instead of stepping into a future month (spec §11.4: "cannot go
  /// past the current month").
  void nextMonth() {
    final next = AppTime.monthAfter(state, 1);
    if (!AppTime.isFutureMonth(next)) state = next;
  }

  /// Jumps to an arbitrary month (the month/year picker), clamped the same
  /// way as [nextMonth].
  void setMonth(DateTime month) {
    final normalized = AppTime.monthStart(month);
    if (!AppTime.isFutureMonth(normalized)) state = normalized;
  }
}
