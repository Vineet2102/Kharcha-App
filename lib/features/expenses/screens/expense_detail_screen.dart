import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Add/edit an expense (spec §11.2). `id` is null for the "new" route.
/// Built out in Phase 5.
class ExpenseDetailScreen extends StatelessWidget {
  const ExpenseDetailScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: id == null ? 'Add expense' : 'Edit expense',
    subtitle: id,
  );
}
