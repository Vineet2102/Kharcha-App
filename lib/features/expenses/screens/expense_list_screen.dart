import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Grouped, searchable, infinite-scroll expense list (spec §11.3). Built
/// out in Phase 5.
class ExpenseListScreen extends StatelessWidget {
  const ExpenseListScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Expenses');
}
