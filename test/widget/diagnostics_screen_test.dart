import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/db/database_provider.dart';
import 'package:kharcha/core/logging/app_logger.dart';
import 'package:kharcha/features/settings/screens/diagnostics_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // A process-wide singleton (spec §9.8) — reset so entries from an
    // earlier test file in the same run don't leak into these assertions.
    AppLogger.instance.clear();
  });

  tearDown(() => db.close());

  Future<void> enqueue(String id, {String? entity}) => db.outboxDao.enqueue(
    OutboxEntriesCompanion.insert(
      id: id,
      entity: entity ?? 'expense',
      entityId: id,
      op: 'upsert',
      payload: jsonEncode({'id': id}),
      createdAt: DateTime.now().toUtc(),
    ),
  );

  Widget harness() => ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const MaterialApp(home: DiagnosticsScreen()),
  );

  testWidgets('shows the sync queue, failed items, and recent logs (T-14.5)', (
    tester,
  ) async {
    await enqueue('pending1', entity: 'expense');
    await enqueue('failed1', entity: 'category');
    await db.outboxDao.markFailed('failed1', 'RLS denied the write');
    AppLogger.instance.info('Sync cycle completed');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('expense · upsert'), findsOneWidget);
    expect(find.text('category · upsert'), findsOneWidget);
    expect(find.text('RLS denied the write'), findsOneWidget);
    expect(find.text('Sync cycle completed'), findsOneWidget);
    expect(find.text('Nothing waiting to sync.'), findsNothing);
    expect(find.text('No failed items.'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('shows empty-state text when there is nothing to show', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    expect(find.text('Nothing waiting to sync.'), findsOneWidget);
    expect(find.text('No failed items.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Retry un-parks a failed entry back to pending (T-14.5)', (
    tester,
  ) async {
    await enqueue('failed1', entity: 'category');
    await db.outboxDao.markFailed('failed1', 'RLS denied the write');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    final due = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(due.map((e) => e.id), ['failed1']);
    expect(find.text('No failed items.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });

  testWidgets('Discard removes a failed entry entirely (T-14.5)', (
    tester,
  ) async {
    await enqueue('failed1', entity: 'category');
    await db.outboxDao.markFailed('failed1', 'RLS denied the write');

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    // A one-shot query, not `.watchFailed().first`: a fresh `.watch()`
    // subscription's notification relies on Drift's real (Timer-based)
    // stream-invalidation plumbing, which never fires under a bare `await`
    // in `testWidgets`' FakeAsync zone — nothing here is pumping the fake
    // clock while we wait, so that await would hang forever. `dueEntries`
    // is a plain one-shot `Future` query with no such dependency; the
    // discarded row is gone outright, so it's absent from every status.
    final remaining = await db.outboxDao.dueEntries(
      DateTime.now().toUtc().add(const Duration(days: 1)),
    );
    expect(remaining, isEmpty);
    expect(find.text('No failed items.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 1));
  });
}
