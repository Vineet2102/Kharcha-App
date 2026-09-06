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

  group('pendingCount / watchPendingCount', () {
    test(
      'counts only pending entries, both the one-shot and stream forms',
      () async {
        await enqueue('e1', DateTime.utc(2026, 9, 1));
        await enqueue('e2', DateTime.utc(2026, 9, 2));
        await db.outboxDao.markFailed('e2', 'permanent error');

        expect(await db.outboxDao.pendingCount(), 1);
        expect(await db.outboxDao.watchPendingCount().first, 1);
      },
    );

    test('zero when the outbox is empty', () async {
      expect(await db.outboxDao.pendingCount(), 0);
    });
  });

  group('watchFailedCount', () {
    test('counts only failed entries', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await enqueue('e2', DateTime.utc(2026, 9, 2));
      await db.outboxDao.markFailed('e2', 'permanent error');

      expect(await db.outboxDao.watchFailedCount().first, 1);
    });
  });

  group('hasStuckEntries', () {
    test('false when no pending entry has failed 5+ times', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await db.outboxDao.recordAttempt('e1', attempts: 4);

      expect(await db.outboxDao.hasStuckEntries(), isFalse);
    });

    test('true once a pending entry has failed 5+ times', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await db.outboxDao.recordAttempt('e1', attempts: 5);

      expect(await db.outboxDao.hasStuckEntries(), isTrue);
    });

    test(
      'a failed (parked) entry with 5+ attempts does not count as stuck',
      () async {
        await enqueue('e1', DateTime.utc(2026, 9, 1));
        await db.outboxDao.recordAttempt('e1', attempts: 5);
        await db.outboxDao.markFailed('e1', 'permanent error');

        expect(await db.outboxDao.hasStuckEntries(), isFalse);
      },
    );
  });

  group('dueEntries', () {
    test(
      'excludes a pending entry still waiting out its backoff timer',
      () async {
        await enqueue('e1', DateTime.utc(2026, 9, 1));
        await db.outboxDao.recordAttempt(
          'e1',
          attempts: 1,
          nextAttemptAt: DateTime.utc(2026, 9, 10),
        );

        final due = await db.outboxDao.dueEntries(DateTime.utc(2026, 9, 5));
        expect(due, isEmpty);
      },
    );

    test('includes an entry once its backoff has elapsed', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));
      await db.outboxDao.recordAttempt(
        'e1',
        attempts: 1,
        nextAttemptAt: DateTime.utc(2026, 9, 2),
      );

      final due = await db.outboxDao.dueEntries(DateTime.utc(2026, 9, 5));
      expect(due, hasLength(1));
    });
  });

  group('remove / removePendingUpsert (Undo snackbar, spec §11.2)', () {
    test('remove deletes the entry outright', () async {
      await enqueue('e1', DateTime.utc(2026, 9, 1));

      final count = await db.outboxDao.remove('e1');

      expect(count, 1);
      expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
    });

    test(
      'removePendingUpsert removes a still-pending create and reports true',
      () async {
        await enqueue('e1', DateTime.utc(2026, 9, 1));

        final removed = await db.outboxDao.removePendingUpsert('expense', 'e1');

        expect(removed, isTrue);
        expect(await db.outboxDao.dueEntries(DateTime.now().toUtc()), isEmpty);
      },
    );

    test('removePendingUpsert reports false when the entry no longer exists '
        '(already pushed, or never existed)', () async {
      final removed = await db.outboxDao.removePendingUpsert(
        'expense',
        'nonexistent',
      );

      expect(removed, isFalse);
    });

    test(
      'removePendingUpsert leaves a delete op alone (only matches upsert)',
      () async {
        await db.outboxDao.enqueue(
          OutboxEntriesCompanion.insert(
            id: 'd1',
            entity: 'expense',
            entityId: 'e1',
            op: 'delete',
            payload: jsonEncode({'id': 'e1'}),
            createdAt: DateTime.utc(2026, 9, 1),
          ),
        );

        final removed = await db.outboxDao.removePendingUpsert('expense', 'e1');

        expect(removed, isFalse);
        expect(
          await db.outboxDao.dueEntries(DateTime.now().toUtc()),
          hasLength(1),
        );
      },
    );
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
