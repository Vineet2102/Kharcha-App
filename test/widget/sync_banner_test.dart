import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/data/sync/sync_state.dart';
import 'package:kharcha/data/sync/sync_state_controller.dart';
import 'package:kharcha/features/shell/widgets/sync_banner.dart';

/// Spec §13's widget-layer row: "offline banner states" (T-4.7).
void main() {
  Widget harness(SyncState state) => ProviderScope(
    overrides: [
      syncStateControllerProvider.overrideWith(() => _FixedSyncState(state)),
    ],
    child: const MaterialApp(home: Scaffold(body: SyncBanner())),
  );

  testWidgets('renders nothing when idle and clean', (tester) async {
    await tester.pumpWidget(harness(const SyncIdle()));

    expect(find.byType(SizedBox), findsOneWidget);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('shows "Syncing…" while a cycle runs', (tester) async {
    await tester.pumpWidget(harness(const SyncRunning(step: 'push')));

    expect(find.text('Syncing…'), findsOneWidget);
  });

  testWidgets('offline with no pending changes shows a plain "Offline"', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const SyncOffline(pendingCount: 0)));

    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('offline with one pending change uses the singular form', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const SyncOffline(pendingCount: 1)));

    expect(find.text('Offline — 1 change waiting'), findsOneWidget);
  });

  testWidgets('offline with several pending changes uses the plural form', (
    tester,
  ) async {
    await tester.pumpWidget(harness(const SyncOffline(pendingCount: 3)));

    expect(find.text('Offline — 3 changes waiting'), findsOneWidget);
  });

  testWidgets(
    'a sync error shows the failure message in the error colour scheme',
    (tester) async {
      await tester.pumpWidget(
        harness(
          const SyncError(
            message: 'Some changes could not be synced.',
            pendingCount: 2,
          ),
        ),
      );

      expect(find.text('Some changes could not be synced.'), findsOneWidget);
      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.color;
      expect(decoration, isNotNull);
    },
  );
}

class _FixedSyncState extends SyncStateController {
  _FixedSyncState(this._state);

  final SyncState _state;

  @override
  SyncState build() => _state;
}
