import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Payment method management, admin-only actions (spec §11.5). Built out
/// in Phase 5.
class PaymentMethodListScreen extends StatelessWidget {
  const PaymentMethodListScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const PlaceholderScreen(title: 'Payment methods');
}
