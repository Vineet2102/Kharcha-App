import 'package:flutter/material.dart';

/// Transient frame while the router's `redirect` (T-3.4) resolves the
/// session and sends the user to `/login` or the dashboard. Supabase/Drift/tz
/// bootstrap itself runs in `main()` (T-3.1), before this ever builds.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
