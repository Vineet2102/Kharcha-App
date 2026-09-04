import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Add/edit a budget (spec §11.7). `id` is null for the "new" route. Built
/// out in Phase 8.
class BudgetDetailScreen extends StatelessWidget {
  const BudgetDetailScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
    title: id == null ? 'Add budget' : 'Edit budget',
    subtitle: id,
  );
}
