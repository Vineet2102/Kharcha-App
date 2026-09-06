import 'package:flutter/widgets.dart';

/// The app's root `Navigator` key, shared between `app_router.dart` (every
/// modal route is pushed on this navigator, spec §10.1) and the
/// notification tap handler (spec §11.12, T-13.4) — the latter needs a
/// `BuildContext` to call `GoRouter.of(context).push(...)` from outside the
/// widget tree, and this key's `currentContext` is the only way to get one.
final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
