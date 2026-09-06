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
}
