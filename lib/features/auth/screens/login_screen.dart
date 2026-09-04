import 'package:flutter/material.dart';

import '../../shell/widgets/placeholder_screen.dart';

/// Email + password only — there is no sign-up screen (spec D2). Built out
/// in Phase 3 (T-3.3).
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const PlaceholderScreen(title: 'Sign in');
}
