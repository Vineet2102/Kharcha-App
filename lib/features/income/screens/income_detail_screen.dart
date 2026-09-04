import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Add/edit an income entry (spec §11.6). `id` is null for the "new" route.
/// Built out in Phase 7.
class IncomeDetailScreen extends StatelessWidget {
  const IncomeDetailScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        title: id == null ? 'Add income' : 'Edit income',
        subtitle: id,
      );
}
