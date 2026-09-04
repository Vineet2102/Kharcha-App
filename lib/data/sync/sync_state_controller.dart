import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'sync_state.dart';

part 'sync_state_controller.g.dart';

/// Publishes [SyncState] for the UI (the sync banner) to watch. `keepAlive`
/// for the same reason as `LoginController`/`SignOutController`: the
/// `SyncEngine` writes to this from background timers and connectivity
/// callbacks that outlive any single screen.
@Riverpod(keepAlive: true)
class SyncStateController extends _$SyncStateController {
  @override
  SyncState build() => const SyncOffline(pendingCount: 0);

  void publish(SyncState next) => state = next;
}
