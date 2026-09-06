import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/remote/household_remote_ds.dart';
import 'package:kharcha/data/repositories/household_repository.dart';

class MockHouseholdRemoteDataSource extends Mock
    implements HouseholdRemoteDataSource {}

void main() {
  late AppDatabase db;
  late HouseholdRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Never touched by the local-first read/write paths under test below
    // (only the RPC-wrapper methods, covered in their own test file, call
    // through to it) — a bare mock is enough.
    repo = HouseholdRepository(MockHouseholdRemoteDataSource(), db, () {});
    final now = DateTime.now().toUtc();
    await db.householdDao.upsert(
      HouseholdsCompanion.insert(
        id: 'h1',
        name: 'Panicker Family',
        createdAt: now,
        updatedAt: now,
      ),
    );
  });
  tearDown(() => db.close());

  test('updateName writes the row and enqueues an outbox upsert', () async {
    await repo.updateName('h1', 'The Panickers');

    final row = await db.householdDao.findById('h1');
    expect(row!.name, 'The Panickers');
    expect(row.isDirty, isTrue);

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
    expect(outbox.single.entity, 'household');
    expect(outbox.single.op, 'upsert');
  });

  test('updateName on an unknown id is a no-op', () async {
    await repo.updateName('missing', 'Anything');

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, isEmpty);
  });

  test('watch reflects the current row', () async {
    expect((await repo.watch('h1').first)!.name, 'Panicker Family');
    await repo.updateName('h1', 'The Panickers');
    expect((await repo.watch('h1').first)!.name, 'The Panickers');
  });
}
