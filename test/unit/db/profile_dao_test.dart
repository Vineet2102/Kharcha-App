import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('upsert then findById round-trips a profile', () async {
    final now = DateTime.utc(2026, 9, 4, 10, 0);
    await db.profileDao.upsert(
      ProfilesCompanion.insert(
        id: 'u1',
        householdId: 'h1',
        displayName: 'Vineet',
        role: const Value('admin'),
        createdAt: now,
        updatedAt: now,
      ),
    );

    final row = await db.profileDao.findById('u1');
    expect(row, isNotNull);
    expect(row!.displayName, 'Vineet');
    expect(row.householdId, 'h1');
    expect(row.role, 'admin');
  });

  test('findById returns null when there is no cached profile yet (offline first launch)', () async {
    final row = await db.profileDao.findById('missing');
    expect(row, isNull);
  });

  test(
    'watchById reflects the latest cached profile (offline-first reads)',
    () async {
      final now = DateTime.utc(2026, 9, 4);
      final stream = db.profileDao.watchById('u1');

      await db.profileDao.upsert(
        ProfilesCompanion.insert(
          id: 'u1',
          householdId: 'h1',
          displayName: 'Rupesh',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final row = await stream.firstWhere((r) => r != null);
      expect(row!.displayName, 'Rupesh');
    },
  );
}
