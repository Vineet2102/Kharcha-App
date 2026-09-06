import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/repositories/profile_repository.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

void main() {
  late AppDatabase db;
  late ProfileRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Never touched by the write paths under test (only `refresh()` reads
    // the network) — a bare mock is enough.
    repo = ProfileRepository(MockSupabaseClient(), db, () {});
    final now = DateTime.now().toUtc();
    await db.profileDao.upsert(
      ProfilesCompanion.insert(
        id: 'u1',
        householdId: 'h1',
        displayName: 'Vineet',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });
  tearDown(() => db.close());

  test(
    'updateDisplayName writes the row and enqueues an outbox upsert',
    () async {
      await repo.updateDisplayName('u1', 'Vineet P');

      final row = await db.profileDao.findById('u1');
      expect(row!.displayName, 'Vineet P');
      expect(row.isDirty, isTrue);

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      expect(outbox, hasLength(1));
      expect(outbox.single.entity, 'profile');
      expect(outbox.single.op, 'upsert');
    },
  );

  test(
    'updateColourHex writes the row and enqueues an outbox upsert',
    () async {
      await repo.updateColourHex('u1', '#FF5722');

      final row = await db.profileDao.findById('u1');
      expect(row!.colourHex, '#FF5722');

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      expect(outbox, hasLength(1));
    },
  );

  test('setActive is callable on another member\'s id (admin toggling, spec '
      'T-14.3) and enqueues an outbox upsert', () async {
    await repo.setActive('u1', false);

    final row = await db.profileDao.findById('u1');
    expect(row!.isActive, isFalse);

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
  });

  test('a write on an unknown id is a no-op', () async {
    await repo.setActive('missing', false);

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, isEmpty);
  });
}
