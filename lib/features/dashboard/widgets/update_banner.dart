import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/repositories/update_check_repository.dart';

/// Dismissible "a new build exists" banner (spec §11.14) — renders nothing
/// unless [UpdateCheckController]'s state is [UpdateAvailable]. `Blocked`
/// is handled separately, as a blocking dialog from `app.dart`, not here.
class UpdateBanner extends ConsumerWidget {
  const UpdateBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final result = ref.watch(updateCheckControllerProvider);
    if (result is! UpdateAvailable) return const SizedBox.shrink();
    final release = result.release;
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Version ${release.versionName} is available',
                style: TextStyle(color: scheme.onPrimaryContainer),
              ),
            ),
            TextButton(
              onPressed: release.downloadUrl == null
                  ? null
                  : () => launchUrl(
                      Uri.parse(release.downloadUrl!),
                      mode: LaunchMode.externalApplication,
                    ),
              child: const Text('Get it'),
            ),
            IconButton(
              icon: Icon(Icons.close, color: scheme.onPrimaryContainer),
              tooltip: 'Dismiss',
              onPressed: () => ref
                  .read(updateCheckControllerProvider.notifier)
                  .dismissBanner(),
            ),
          ],
        ),
      ),
    );
  }
}
