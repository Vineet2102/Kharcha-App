import 'package:flutter/material.dart';

/// A titled card with an optional "See all" action — the shared shape of
/// every Dashboard card (spec §11.4) and every Analytics chart card (spec
/// §11.10).
class SectionCard extends StatelessWidget {
  const SectionCard({required this.title, required this.child, this.onSeeAll, super.key});

  final String title;
  final Widget child;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                if (onSeeAll != null)
                  TextButton(onPressed: onSeeAll, child: const Text('See all')),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

/// The "No data for this period" message every chart/card must show instead
/// of an empty or divide-by-zero rendering (spec §11.10 rules, T-6.5).
class EmptySectionBody extends StatelessWidget {
  const EmptySectionBody({
    this.message = 'No data for this period.',
    super.key,
  });
  final String message;

  @override
  Widget build(BuildContext context) => Text(
    message,
    style: Theme.of(context).textTheme.bodyMedium
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
  );
}
