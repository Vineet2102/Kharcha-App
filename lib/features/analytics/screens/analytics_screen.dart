import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/money/money.dart';
import '../../../core/time/app_time.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/payment_method_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/report_repository.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../domain/models/report.dart';
import '../../dashboard/controllers/selected_month_controller.dart';
import '../../dashboard/widgets/month_selector.dart';
import '../../dashboard/widgets/section_card.dart';

/// Charts (spec §11.10, T-11.1..T-11.4). Every chart reads a live Drift
/// aggregate (`ReportDao`/`ReportRepository`) scoped to the month picked by
/// the shared [selectedMonthControllerProvider] — the same month the
/// Dashboard shows — except the monthly trend and member-comparison charts,
/// which always show the trailing 12/6 months ending at that month.
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthControllerProvider);

    return Scaffold(
      appBar: AppBar(title: MonthSelector(month: month)),
      body: RefreshIndicator(
        onRefresh: () => ref.read(syncEngineProvider).sync(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SectionCard(
              title: 'Monthly trend',
              child: _MonthlyTrendChart(endMonth: month),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Category breakdown',
              child: _CategoryDonutChart(monthStart: month),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Member comparison',
              child: _MemberComparisonChart(endMonth: month),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Payment method split',
              child: _PaymentMethodSplit(monthStart: month),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Day-of-week pattern',
              child: _DayOfWeekChart(monthStart: month),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Top merchants',
              child: _TopMerchantsList(monthStart: month),
            ),
            const SizedBox(height: 12),
            SectionCard(
              title: 'Month-over-month by category',
              child: _MonthOverMonthTable(endMonth: month),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

/// "Monthly trend" (spec §11.10): line chart, last 12 months, expense line
/// + income line, tap a point for the exact value.
class _MonthlyTrendChart extends ConsumerWidget {
  const _MonthlyTrendChart({required this.endMonth});
  final DateTime endMonth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    return StreamBuilder<List<MonthlyTotal>>(
      stream: repo.watchMonthlyTrend(
        householdId: AppConstants.seedHouseholdId,
        endMonth: endMonth,
        months: 12,
      ),
      builder: (context, snapshot) {
        final totals = snapshot.data ?? const <MonthlyTotal>[];
        final hasData = totals.any(
          (t) => t.expensePaise != 0 || t.incomePaise != 0,
        );
        if (!hasData) return const EmptySectionBody();

        final colorScheme = Theme.of(context).colorScheme;
        final incomeColor = Colors.green.shade600;
        var maxValue = 0;
        for (final t in totals) {
          if (t.expensePaise > maxValue) maxValue = t.expensePaise;
          if (t.incomePaise > maxValue) maxValue = t.incomePaise;
        }
        final maxY = maxValue == 0 ? 1.0 : maxValue * 1.15;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 220,
              child: LineChart(
                LineChartData(
                  minY: 0,
                  maxY: maxY,
                  minX: 0,
                  maxX: (totals.length - 1).toDouble(),
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) => Text(
                          Money(value.round()).format(
                            compact: true,
                            withSymbol: false,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 || i >= totals.length) {
                            return const SizedBox.shrink();
                          }
                          final isLast = i == totals.length - 1;
                          if (totals.length > 6 && i.isOdd && !isLast) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              AppTime.monthLabelShort(
                                totals[i].month,
                              ).split(' ').first,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  lineTouchData: LineTouchData(
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipItems: (spots) => [
                        for (final spot in spots)
                          LineTooltipItem(
                            Money(spot.y.round()).format(),
                            TextStyle(color: spot.bar.color),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < totals.length; i++)
                          FlSpot(i.toDouble(), totals[i].expensePaise.toDouble()),
                      ],
                      color: colorScheme.error,
                      barWidth: 2.5,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                    ),
                    LineChartBarData(
                      spots: [
                        for (var i = 0; i < totals.length; i++)
                          FlSpot(i.toDouble(), totals[i].incomePaise.toDouble()),
                      ],
                      color: incomeColor,
                      barWidth: 2.5,
                      isCurved: false,
                      dotData: const FlDotData(show: false),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _LegendDot(color: colorScheme.error, label: 'Expense'),
                const SizedBox(width: 16),
                _LegendDot(color: incomeColor, label: 'Income'),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "Category breakdown" (spec §11.10): donut, current period, top 8
/// categories + "Other", legend with amounts and %.
class _CategoryDonutChart extends ConsumerWidget {
  const _CategoryDonutChart({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};

    return StreamBuilder<List<GroupedTotal>>(
      stream: repo.watchAllCategoryTotals(
        householdId: AppConstants.seedHouseholdId,
        monthStart: monthStart,
      ),
      builder: (context, snapshot) {
        final totals = snapshot.data ?? const <GroupedTotal>[];
        if (totals.isEmpty) return const EmptySectionBody();

        final top8 = totals.take(8).toList();
        final otherPaise = totals
            .skip(8)
            .fold<int>(0, (sum, g) => sum + g.amountPaise);
        final grandTotal =
            top8.fold<int>(0, (sum, g) => sum + g.amountPaise) + otherPaise;

        final slices = <(String label, int amount, Color color)>[
          for (final g in top8)
            (
              categoriesById[g.key]?.name ?? 'Uncategorised',
              g.amountPaise,
              categoriesById[g.key] == null
                  ? Colors.grey
                  : colourFromHex(categoriesById[g.key]!.colourHex),
            ),
          if (otherPaise > 0) ('Other', otherPaise, Colors.grey.shade500),
        ];

        return Column(
          children: [
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: [
                    for (final slice in slices)
                      PieChartSectionData(
                        value: slice.$2.toDouble(),
                        color: slice.$3,
                        radius: 50,
                        showTitle: false,
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
            const SizedBox(height: 12),
            for (final slice in slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slice.$3,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(slice.$1)),
                    Text(
                      '${grandTotal == 0 ? 0 : (slice.$2 / grandTotal * 100).toStringAsFixed(0)}%',
                    ),
                    const SizedBox(width: 8),
                    Text(Money(slice.$2).format()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Member comparison" (spec §11.10): grouped bar chart, last 6 months ×
/// members.
class _MemberComparisonChart extends ConsumerWidget {
  const _MemberComparisonChart({required this.endMonth});
  final DateTime endMonth;

  static const _months = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];

    return StreamBuilder<List<MemberMonthTotal>>(
      stream: repo.watchMemberMonthlyTrend(
        householdId: AppConstants.seedHouseholdId,
        endMonth: endMonth,
        months: _months,
      ),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <MemberMonthTotal>[];
        if (rows.isEmpty) return const EmptySectionBody();

        final months = [
          for (var i = 0; i < _months; i++)
            AppTime.monthAfter(endMonth, -(_months - 1) + i),
        ];
        final byKey = {for (final r in rows) (r.month, r.userId): r.amountPaise};
        final activeProfiles = profiles
            .where((p) => rows.any((r) => r.userId == p.id))
            .toList();
        if (activeProfiles.isEmpty) return const EmptySectionBody();

        var maxValue = 0;
        for (final r in rows) {
          if (r.amountPaise > maxValue) maxValue = r.amountPaise;
        }

        return Column(
          children: [
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  maxY: maxValue == 0 ? 1 : maxValue * 1.15,
                  gridData: const FlGridData(drawVerticalLine: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(),
                    rightTitles: const AxisTitles(),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 48,
                        getTitlesWidget: (value, meta) => Text(
                          Money(value.round()).format(
                            compact: true,
                            withSymbol: false,
                          ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 24,
                        getTitlesWidget: (value, meta) {
                          final i = value.round();
                          if (i < 0 || i >= months.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              AppTime.monthLabelShort(
                                months[i],
                              ).split(' ').first,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                          BarTooltipItem(
                            '${activeProfiles[rodIndex].displayName}\n'
                            '${Money(rod.toY.round()).format()}',
                            const TextStyle(color: Colors.white),
                          ),
                    ),
                  ),
                  barGroups: [
                    for (var i = 0; i < months.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          for (final profile in activeProfiles)
                            BarChartRodData(
                              toY: (byKey[(months[i], profile.id)] ?? 0)
                                  .toDouble(),
                              color: colourFromHex(profile.colourHex),
                              width: 12,
                            ),
                        ],
                      ),
                  ],
                ),
                duration: const Duration(milliseconds: 250),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              children: [
                for (final profile in activeProfiles)
                  _LegendDot(
                    color: colourFromHex(profile.colourHex),
                    label: profile.displayName,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// "Payment method split" (spec §11.10): horizontal bar, current period.
/// Implemented as a plain proportional-bar list rather than forcing
/// `fl_chart` into a horizontal orientation it doesn't natively support —
/// simpler and matches the Dashboard's existing per-member bars.
class _PaymentMethodSplit extends ConsumerWidget {
  const _PaymentMethodSplit({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final methods = ref.watch(paymentMethodsProvider).value ?? const [];
    final methodsById = {for (final m in methods) m.id: m};

    return StreamBuilder<List<GroupedTotal>>(
      stream: repo.watchExpenseByPaymentMethod(
        householdId: AppConstants.seedHouseholdId,
        monthStart: monthStart,
      ),
      builder: (context, snapshot) {
        final totals = snapshot.data ?? const <GroupedTotal>[];
        if (totals.isEmpty) return const EmptySectionBody();

        final grandTotal = totals.fold<int>(0, (sum, g) => sum + g.amountPaise);
        return Column(
          children: [
            for (final g in totals)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(methodsById[g.key]?.name ?? 'Unknown'),
                        Text(Money(g.amountPaise).format()),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: grandTotal == 0
                            ? 0
                            : (g.amountPaise / grandTotal).clamp(0, 1).toDouble(),
                        minHeight: 8,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Day-of-week pattern" (spec §11.10): bar chart, average spend by
/// weekday over the selected month.
class _DayOfWeekChart extends ConsumerWidget {
  const _DayOfWeekChart({required this.monthStart});
  final DateTime monthStart;

  static const _labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final monthEnd = AppTime.monthAfter(monthStart, 1);

    return StreamBuilder<List<WeekdayTotal>>(
      stream: repo.watchExpenseByWeekday(
        householdId: AppConstants.seedHouseholdId,
        monthStart: monthStart,
      ),
      builder: (context, snapshot) {
        final totals = snapshot.data ?? const <WeekdayTotal>[];
        if (totals.isEmpty || totals.every((t) => t.totalPaise == 0)) {
          return const EmptySectionBody();
        }

        final occurrences = <int, int>{for (var w = 1; w <= 7; w++) w: 0};
        for (var d = monthStart; d.isBefore(monthEnd); d = d.add(const Duration(days: 1))) {
          occurrences[d.weekday] = (occurrences[d.weekday] ?? 0) + 1;
        }
        final totalByWeekday = {for (final t in totals) t.weekday: t.totalPaise};
        final averages = <int, int>{
          for (var w = 1; w <= 7; w++)
            w: occurrences[w]! == 0
                ? 0
                : ((totalByWeekday[w] ?? 0) / occurrences[w]!).round(),
        };
        final maxAverage = averages.values.fold(0, (a, b) => a > b ? a : b);

        return SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxAverage == 0 ? 1 : maxAverage * 1.15,
              gridData: const FlGridData(drawVerticalLine: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 48,
                    getTitlesWidget: (value, meta) => Text(
                      Money(value.round()).format(compact: true, withSymbol: false),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) {
                      final i = value.round();
                      if (i < 0 || i >= _labels.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _labels[i],
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(
                        Money(rod.toY.round()).format(),
                        const TextStyle(color: Colors.white),
                      ),
                ),
              ),
              barGroups: [
                for (var w = 1; w <= 7; w++)
                  BarChartGroupData(
                    x: w - 1,
                    barRods: [
                      BarChartRodData(
                        toY: averages[w]!.toDouble(),
                        color: Theme.of(context).colorScheme.primary,
                        width: 18,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  ),
              ],
            ),
            duration: const Duration(milliseconds: 250),
          ),
        );
      },
    );
  }
}

/// "Top merchants" (spec §11.10): simple ranked list, top 10 by total.
class _TopMerchantsList extends ConsumerWidget {
  const _TopMerchantsList({required this.monthStart});
  final DateTime monthStart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    return StreamBuilder<List<GroupedTotal>>(
      stream: repo.watchTopMerchants(
        householdId: AppConstants.seedHouseholdId,
        monthStart: monthStart,
      ),
      builder: (context, snapshot) {
        final totals = snapshot.data ?? const <GroupedTotal>[];
        if (totals.isEmpty) return const EmptySectionBody();

        return Column(
          children: [
            for (var i = 0; i < totals.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${i + 1}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Expanded(child: Text(totals[i].key)),
                    Text(Money(totals[i].amountPaise).format()),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Month-over-month table" (spec §11.10): category × last 3 months with
/// Δ% and colour coding (red = spend increased, green = spend decreased —
/// same convention as the Dashboard's month-over-month arrow).
class _MonthOverMonthTable extends ConsumerWidget {
  const _MonthOverMonthTable({required this.endMonth});
  final DateTime endMonth;

  static const _months = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(reportRepositoryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final categoriesById = {for (final c in categories) c.id: c};

    return StreamBuilder<List<CategoryMonthTotal>>(
      stream: repo.watchCategoryMonthlyTrend(
        householdId: AppConstants.seedHouseholdId,
        endMonth: endMonth,
        months: _months,
      ),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const <CategoryMonthTotal>[];
        if (rows.isEmpty) return const EmptySectionBody();

        final months = [
          for (var i = 0; i < _months; i++)
            AppTime.monthAfter(endMonth, -(_months - 1) + i),
        ];
        final byKey = {
          for (final r in rows) (r.month, r.categoryId): r.amountPaise,
        };
        final categoryIds = rows.map((r) => r.categoryId).toSet().toList()
          ..sort((a, b) {
            final aLast = byKey[(months.last, a)] ?? 0;
            final bLast = byKey[(months.last, b)] ?? 0;
            return bLast.compareTo(aLast);
          });

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: [
              const DataColumn(label: Text('Category')),
              for (final m in months)
                DataColumn(
                  label: Text(AppTime.monthLabelShort(m).split(' ').first),
                  numeric: true,
                ),
              const DataColumn(label: Text('Δ%'), numeric: true),
            ],
            rows: [
              for (final categoryId in categoryIds)
                DataRow(
                  cells: [
                    DataCell(
                      Text(categoriesById[categoryId]?.name ?? 'Unknown'),
                    ),
                    for (final m in months)
                      DataCell(
                        Text(
                          Money(byKey[(m, categoryId)] ?? 0).format(
                            compact: true,
                          ),
                        ),
                      ),
                    DataCell(_DeltaCell(
                      previous: byKey[(months[months.length - 2], categoryId)] ?? 0,
                      current: byKey[(months.last, categoryId)] ?? 0,
                    )),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _DeltaCell extends StatelessWidget {
  const _DeltaCell({required this.previous, required this.current});
  final int previous;
  final int current;

  @override
  Widget build(BuildContext context) {
    if (previous == 0) {
      return Text(
        current == 0 ? '—' : 'new',
        style: Theme.of(context).textTheme.bodyMedium,
      );
    }
    final pct = (current - previous) / previous * 100;
    final color = pct > 0
        ? Theme.of(context).colorScheme.error
        : Colors.green.shade700;
    final sign = pct > 0 ? '+' : '';
    return Text(
      '$sign${pct.toStringAsFixed(0)}%',
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
    );
  }
}
