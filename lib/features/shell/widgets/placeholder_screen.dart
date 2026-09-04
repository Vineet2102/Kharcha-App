import 'package:flutter/material.dart';

/// Temporary body for a route until its real feature screen is built in a
/// later phase. Phase 2 scope only needs every route to navigate cleanly.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(subtitle!, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}
