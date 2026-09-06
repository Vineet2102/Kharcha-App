import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> enqueue(String id, DateTime createdAt) => db.outboxDao.enqueue(
    OutboxEntriesCompanion.insert(
      id: id,
      entity: 'expense',
      entityId: id,
      op: 'upsert',
      payload: jsonEncode({'id': id}),
      createdAt: createdAt,
    ),
  );

  group('oldestPendingCreatedAt', () {
    test('null when the outbox is empty', () async {
      expect(await db.outboxDao.oldestPendingCreatedAt(), isNull);
    });

    test('returns the earliest createdAt among pending entries', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 3));
      await enqueue('e2', DateTime.utc(2026, 9, 1));
      await enqueue('e3', DateTime.utc(2026, 9, 5));

      // Drift decodes a DateTime column as local-flagged even though the
      // stored instant is correct (see DECISIONS.md, Phase 4) — normalise
      // with `.toUtc()` before comparing, same convention as every other
      // read site in this app.
      final oldest = await db.outboxDao.oldestPendingCreatedAt();
      expect(oldest?.toUtc(), DateTime.utc(2026, 9, 1));
    });

    test('ignores entries already marked failed', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await enqueue('e2', DateTime.utc(2026, 9, 5));
      await db.outboxDao.markFailed('e1', 'permanent error');

      final oldest = await db.outboxDao.oldestPendingCreatedAt();
      expect(oldest?.toUtc(), DateTime.utc(2026, 9, 5));
    });
  });

  group('watchPending/watchFailed (Diagnostics screen, T-14.5)', () {
    test('watchPending excludes failed entries', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await enqueue('e2', DateTime.utc(2026, 9, 2));
      await db.outboxDao.markFailed('e2', 'permanent error');

      final pending = await db.outboxDao.watchPending().first;
      expect(pending.map((e) => e.id), ['e1']);
    });

    test('watchFailed only returns failed entries', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await enqueue('e2', DateTime.utc(2026, 9, 2));
      await db.outboxDao.markFailed('e2', 'permanent error');

      final failed = await db.outboxDao.watchFailed().first;
      expect(failed.map((e) => e.id), ['e2']);
      expect(failed.single.lastError, 'permanent error');
    });
  });

  group('retry', () {
    test(
      'un-parks a failed entry back to pending, clearing attempts/error',
      () async {
        await enqueue('e1', DateTime.utc(2026, 9, 1));
        await db.outboxDao.recordAttempt(
          'e1',
          attempts: 3,
          error: 'transient error',
          nextAttemptAt: DateTime.utc(2026, 9, 2),
        );
        await db.outboxDao.markFailed('e1', 'permanent error');

        await db.outboxDao.retry('e1');

        final due = await db.outboxDao.dueEntries(DateTime.now().toUtc());
        expect(due, hasLength(1));
        expect(due.single.attempts, 0);
        expect(due.single.lastError, isNull);
        expect(due.single.nextAttemptAt, isNull);
      },
    );
  });
}
