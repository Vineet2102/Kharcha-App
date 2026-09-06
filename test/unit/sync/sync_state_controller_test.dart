import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/data/sync/sync_state.dart';
import 'package:kharcha/data/sync/sync_state_controller.dart';

void main() {
  test('starts offline with an empty pending count, and publish() updates '
      'the watched state', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(syncStateControllerProvider), isA<SyncOffline>());

    container
        .read(syncStateControllerProvider.notifier)
        .publish(const SyncIdle(lastSyncedAt: null));

    expect(container.read(syncStateControllerProvider), isA<SyncIdle>());
  });
}
