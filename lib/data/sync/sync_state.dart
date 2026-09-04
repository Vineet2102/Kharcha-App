/// State exposed to the UI by the [SyncEngine] (spec §9.6), rendered as a
/// slim banner under the app bar.
sealed class SyncState {
  const SyncState();
}

/// Nothing pending, no error — the banner renders nothing in this state.
final class SyncIdle extends SyncState {
  const SyncIdle({this.lastSyncedAt});

  final DateTime? lastSyncedAt;
}

/// A push/pull cycle is in flight.
final class SyncRunning extends SyncState {
  const SyncRunning({this.step});

  final String? step;
}

/// No network path. `pendingCount` is the number of outbox entries still
/// waiting to be pushed once back online.
final class SyncOffline extends SyncState {
  const SyncOffline({required this.pendingCount});

  final int pendingCount;
}

/// The last cycle failed. Per spec §9.6, this is only surfaced once at
/// least one outbox entry has failed 5+ times — a single transient blip
/// should not alarm the user.
final class SyncError extends SyncState {
  const SyncError({required this.message, required this.pendingCount});

  final String message;
  final int pendingCount;
}
