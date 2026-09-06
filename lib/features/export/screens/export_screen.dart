import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/constants/category_visuals.dart';
import '../../../core/errors/failure.dart';
import '../../../core/result/result.dart';
import '../../../core/time/app_time.dart';
import '../../../data/repositories/category_repository.dart';
import '../../../data/repositories/export_repository.dart';
import '../../../data/repositories/profile_repository.dart';

enum _ExportFormat { csv, pdf }

enum _DateScope { thisMonth, lastMonth, allTime, custom }

/// Export screen (spec §11.11, T-12.3): date range (month presets + custom),
/// member/category scope, CSV or PDF, plus an admin-only full JSON backup.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  _DateScope _scope = _DateScope.thisMonth;
  DateTime? _customStart;
  DateTime? _customEnd;
  final Set<String> _memberIds = {};
  final Set<String> _categoryIds = {};
  bool _includeIncome = true;
  _ExportFormat _format = _ExportFormat.csv;
  bool _transactionAppendix = false;
  bool _busy = false;

  DateTime? get _startDate => switch (_scope) {
    _DateScope.thisMonth => AppTime.monthStart(DateTime.now().toUtc()),
    _DateScope.lastMonth => AppTime.monthAfter(
      AppTime.monthStart(DateTime.now().toUtc()),
      -1,
    ),
    _DateScope.allTime => null,
    _DateScope.custom => _customStart,
  };

  DateTime? get _endDate => switch (_scope) {
    _DateScope.thisMonth => AppTime.monthAfter(
      AppTime.monthStart(DateTime.now().toUtc()),
      1,
    ).subtract(const Duration(days: 1)),
    _DateScope.lastMonth => AppTime.monthStart(
      DateTime.now().toUtc(),
    ).subtract(const Duration(days: 1)),
    _DateScope.allTime => null,
    _DateScope.custom => _customEnd,
  };

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: _customStart != null && _customEnd != null
          ? DateTimeRange(start: _customStart!, end: _customEnd!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _scope = _DateScope.custom;
      _customStart = DateTime.utc(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _customEnd = DateTime.utc(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      );
    });
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    final repo = ref.read(exportRepositoryProvider);
    final start = _startDate;
    final end = _endDate;
    final files = <File>[];
    Failure? failure;

    void collect(Result<File, Failure> result) {
      final value = result.valueOrNull;
      if (value != null) {
        files.add(value);
      } else {
        failure ??= result.failureOrNull;
      }
    }

    if (_format == _ExportFormat.csv) {
      collect(
        await repo.exportExpensesCsv(
          householdId: AppConstants.seedHouseholdId,
          startDate: start,
          endDate: end,
          memberIds: _memberIds.toList(),
          categoryIds: _categoryIds.toList(),
        ),
      );
      if (_includeIncome && failure == null) {
        collect(
          await repo.exportIncomeCsv(
            householdId: AppConstants.seedHouseholdId,
            startDate: start,
            endDate: end,
            memberIds: _memberIds.toList(),
            categoryIds: _categoryIds.toList(),
          ),
        );
      }
    } else {
      collect(
        await repo.exportPdfReport(
          householdId: AppConstants.seedHouseholdId,
          startDate: start,
          endDate: end,
          memberIds: _memberIds.toList(),
          categoryIds: _categoryIds.toList(),
          transactionAppendix: _transactionAppendix,
        ),
      );
    }

    if (!mounted) return;
    setState(() => _busy = false);
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure!.message)));
      return;
    }
    await SharePlus.instance.share(
      ShareParams(files: files.map((f) => XFile(f.path)).toList()),
    );
  }

  Future<void> _exportFullBackup() async {
    setState(() => _busy = true);
    final result = await ref
        .read(exportRepositoryProvider)
        .exportFullBackupJson(householdId: AppConstants.seedHouseholdId);
    if (!mounted) return;
    setState(() => _busy = false);
    final file = result.valueOrNull;
    if (file != null) {
      await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
    } else {
      final failure = result.failureOrNull;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(failure?.message ?? 'Something went wrong.')),
      );
    }
  }

  String get _rangeLabel {
    final start = _startDate;
    final end = _endDate;
    if (start == null && end == null) return 'All time';
    return '${_fmt(start!)} – ${_fmt(end!)}';
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final profiles = ref.watch(householdProfilesProvider).value ?? const [];
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final isAdmin = ref.watch(currentProfileProvider).value?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Export')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Date range', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('This month'),
                    selected: _scope == _DateScope.thisMonth,
                    onSelected: (_) =>
                        setState(() => _scope = _DateScope.thisMonth),
                  ),
                  ChoiceChip(
                    label: const Text('Last month'),
                    selected: _scope == _DateScope.lastMonth,
                    onSelected: (_) =>
                        setState(() => _scope = _DateScope.lastMonth),
                  ),
                  ChoiceChip(
                    label: const Text('All time'),
                    selected: _scope == _DateScope.allTime,
                    onSelected: (_) =>
                        setState(() => _scope = _DateScope.allTime),
                  ),
                  ActionChip(
                    label: Text(
                      _scope == _DateScope.custom
                          ? _rangeLabel
                          : 'Custom range',
                    ),
                    onPressed: _pickCustomRange,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(_rangeLabel, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 20),
              if (profiles.isNotEmpty) ...[
                Text('Members', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final profile in profiles)
                      FilterChip(
                        label: Text(profile.displayName),
                        selected: _memberIds.contains(profile.id),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _memberIds.add(profile.id)
                              : _memberIds.remove(profile.id);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              if (categories.isNotEmpty) ...[
                Text(
                  'Categories',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final category in categories)
                      FilterChip(
                        avatar: Icon(iconForKey(category.iconKey), size: 18),
                        label: Text(category.name),
                        selected: _categoryIds.contains(category.id),
                        onSelected: (selected) => setState(() {
                          selected
                              ? _categoryIds.add(category.id)
                              : _categoryIds.remove(category.id);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
              ],
              Text('Format', style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 8),
              SegmentedButton<_ExportFormat>(
                segments: const [
                  ButtonSegment(value: _ExportFormat.csv, label: Text('CSV')),
                  ButtonSegment(
                    value: _ExportFormat.pdf,
                    label: Text('PDF report'),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: (s) => setState(() => _format = s.first),
              ),
              if (_format == _ExportFormat.csv)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include income'),
                  subtitle: const Text('A second CSV file for income'),
                  value: _includeIncome,
                  onChanged: (v) => setState(() => _includeIncome = v),
                )
              else
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Include full transaction list'),
                  subtitle: const Text('Appendix at the end of the report'),
                  value: _transactionAppendix,
                  onChanged: (v) => setState(() => _transactionAppendix = v),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _export,
                icon: const Icon(Icons.ios_share),
                label: Text(
                  _format == _ExportFormat.csv ? 'Export CSV' : 'Export PDF',
                ),
              ),
              if (isAdmin) ...[
                const Divider(height: 40),
                Text(
                  'Full backup',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'A single JSON file with every table\'s rows for this '
                  'household — the disaster-recovery escape hatch. Store it '
                  'in Google Drive periodically.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _exportFullBackup,
                  icon: const Icon(Icons.backup_outlined),
                  label: const Text('Export full backup (JSON)'),
                ),
              ],
              if (_busy) ...[
                const SizedBox(height: 20),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
