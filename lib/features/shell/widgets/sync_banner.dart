import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/sync_state.dart';
import '../../../data/sync/sync_state_controller.dart';

/// Slim strip under the app bar reflecting [SyncState] (spec §9.6 T-4.7):
/// nothing when idle and clean, `Syncing…` while a cycle runs, `Offline —
/// N changes waiting` with no network, or the failure message once outbox
/// entries are stuck.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(syncStateControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    final String? text;
    final Color background;
    final Color foreground;
    switch (state) {
      case SyncIdle():
        text = null;
        background = scheme.surfaceContainerHighest;
        foreground = scheme.onSurfaceVariant;
      case SyncRunning():
        text = 'Syncing…';
        background = scheme.surfaceContainerHighest;
        foreground = scheme.onSurfaceVariant;
      case SyncOffline(:final pendingCount):
        text = pendingCount == 0
            ? 'Offline'
            : 'Offline — $pendingCount change${pendingCount == 1 ? '' : 's'} waiting';
        background = scheme.surfaceContainerHighest;
        foreground = scheme.onSurfaceVariant;
      case SyncError(:final message):
        text = message;
        background = scheme.errorContainer;
        foreground = scheme.onErrorContainer;
    }

    if (text == null) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: foreground),
      ),
    );
  }
}
