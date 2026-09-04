import 'package:flutter/material.dart';

/// Bootstraps Supabase, Drift, and timezone data, then decides where the
/// router should send the user. Real bootstrap logic lands in Phase 3
/// (T-3.1, T-3.4).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
