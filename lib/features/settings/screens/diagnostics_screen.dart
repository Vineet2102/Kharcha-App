import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Outbox contents, failed items, log viewer (spec §9.8, T-14.5). Built out
/// in Phase 14.
class DiagnosticsScreen extends StatelessWidget {
  const DiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Diagnostics');
}
