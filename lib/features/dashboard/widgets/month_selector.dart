import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/app_time.dart';
import '../controllers/selected_month_controller.dart';

/// The month stepper + year/month-grid picker shared by the Dashboard and
/// Analytics (spec §11.10: "Month/range selector shared with the
/// Dashboard") — both read and write the same [selectedMonthControllerProvider]
/// so switching tabs keeps the same selected month.
class MonthSelector extends ConsumerWidget {
  const MonthSelector({required this.month, super.key});
  final DateTime month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(selectedMonthControllerProvider.notifier);
    final isCurrentMonth = AppTime.isSameIstMonth(
      month,
      DateTime.now().toUtc(),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: controller.previousMonth,
          tooltip: 'Previous month',
        ),
        Expanded(
          child: TextButton(
            onPressed: () async {
              final picked = await showDialog<DateTime>(
                context: context,
                builder: (context) => _MonthYearPickerDialog(initial: month),
              );
              if (picked != null) controller.setMonth(picked);
            },
            child: Text(AppTime.monthLabel(month)),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: isCurrentMonth ? null : controller.nextMonth,
          tooltip: 'Next month',
        ),
      ],
    );
  }
}

class _MonthYearPickerDialog extends StatefulWidget {
  const _MonthYearPickerDialog({required this.initial});
  final DateTime initial;

  @override
  State<_MonthYearPickerDialog> createState() => _MonthYearPickerDialogState();
}

class _MonthYearPickerDialogState extends State<_MonthYearPickerDialog> {
  late int _year = widget.initial.year;

  @override
  Widget build(BuildContext context) {
    final canGoForward = _year < AppTime.nowIst().year;
    return AlertDialog(
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: () => setState(() => _year--),
          ),
          Text('$_year'),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: canGoForward ? () => setState(() => _year++) : null,
          ),
        ],
      ),
      content: SizedBox(
        width: 300,
        child: GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          childAspectRatio: 2,
          children: [
            for (var m = 1; m <= 12; m++) _MonthCell(year: _year, month: m),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _MonthCell extends StatelessWidget {
  const _MonthCell({required this.year, required this.month});
  final int year;
  final int month;

  @override
  Widget build(BuildContext context) {
    final value = DateTime.utc(year, month);
    final disabled = AppTime.isFutureMonth(value);
    return TextButton(
      onPressed: disabled ? null : () => Navigator.of(context).pop(value),
      child: Text(AppTime.monthLabelShort(value).split(' ').first),
    );
  }
}
