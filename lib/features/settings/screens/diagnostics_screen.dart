import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/db/app_database.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/logging/app_logger.dart';

/// Outbox contents, failed items, log viewer (spec §9.8, §11.13, T-14.5) —
/// "You can diagnose a sync failure on a family member's phone using only
/// the Diagnostics screen" (Gate 14's own acceptance line).
class DiagnosticsScreen extends ConsumerWidget {
  const DiagnosticsScreen({super.key});

  Future<void> _shareLogs(BuildContext context) async {
    final dir = await getTemporaryDirectory();
    final file = File(p.join(dir.path, 'kharcha_logs.txt'));
    await file.writeAsString(
      AppLogger.instance.exportAsText(),
      flush: true,
    );
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Share logs',
            onPressed: () => _shareLogs(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader('Sync queue'),
          StreamBuilder<List<OutboxEntry>>(
            stream: db.outboxDao.watchPending(),
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const [];
              if (entries.isEmpty) {
                return const _EmptyRow('Nothing waiting to sync.');
              }
              return Column(
                children: [
                  for (final entry in entries) _OutboxTile(entry: entry),
                ],
              );
            },
          ),
          const Divider(height: 24),
          _SectionHeader('Failed items'),
          StreamBuilder<List<OutboxEntry>>(
            stream: db.outboxDao.watchFailed(),
            builder: (context, snapshot) {
              final entries = snapshot.data ?? const [];
              if (entries.isEmpty) {
                return const _EmptyRow('No failed items.');
              }
              return Column(
                children: [
                  for (final entry in entries)
                    _OutboxTile(
                      entry: entry,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () =>
                                db.outboxDao.retry(entry.id),
                            child: const Text('Retry'),
                          ),
                          TextButton(
                            onPressed: () =>
                                db.outboxDao.remove(entry.id),
                            child: const Text('Discard'),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const Divider(height: 24),
          _SectionHeader('Recent logs'),
          for (final entry in AppLogger.instance.recentEntries.reversed)
            _LogTile(entry: entry),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _OutboxTile extends StatelessWidget {
  const _OutboxTile({required this.entry, this.trailing});

  final OutboxEntry entry;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text('${entry.entity} · ${entry.op}'),
      subtitle: Text(
        entry.lastError == null
            ? 'Created ${entry.createdAt.toLocal()} · ${entry.attempts} attempt(s)'
            : entry.lastError!,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: trailing,
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({required this.entry});

  final LogEntry entry;

  Color _colourFor(BuildContext context, LogLevel level) {
    final scheme = Theme.of(context).colorScheme;
    return switch (level) {
      LogLevel.error => scheme.error,
      LogLevel.warn => Colors.orange,
      LogLevel.info => scheme.onSurface,
      LogLevel.debug => scheme.onSurfaceVariant,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(
        entry.message,
        style: TextStyle(color: _colourFor(context, entry.level)),
      ),
      subtitle: Text(entry.error == null
          ? entry.timestamp.toLocal().toString()
          : '${entry.timestamp.toLocal()} — ${entry.error}'),
    );
  }
}
