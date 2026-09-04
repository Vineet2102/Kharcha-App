import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a broadcast [Stream] (Supabase's `onAuthStateChange`) to
/// go_router's `Listenable`-based `refreshListenable`, so the router
/// re-evaluates `redirect` on every sign-in/sign-out (spec T-3.4).
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
