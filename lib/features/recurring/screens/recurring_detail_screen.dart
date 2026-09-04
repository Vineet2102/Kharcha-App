import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Add/edit a recurring rule (spec §11.8). `id` is null for the "new"
/// route. Built out in Phase 9.
class RecurringDetailScreen extends StatelessWidget {
  const RecurringDetailScreen({super.key, this.id});

  final String? id;

  @override
  Widget build(BuildContext context) => PlaceholderScreen(
        title: id == null ? 'Add recurring rule' : 'Edit recurring rule',
        subtitle: id,
      );
}
