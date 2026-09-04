import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Recurring rules list (spec §11.8). Built out in Phase 9.
class RecurringListScreen extends StatelessWidget {
  const RecurringListScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Recurring');
}
