import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'wipeAll empties every table (spec T-3.6, sign-out privacy wipe)',
    () async {
      final now = DateTime.utc(2026, 9, 4);

      await db.profileDao.upsert(
        ProfilesCompanion.insert(
          id: 'u1',
          householdId: 'h1',
          displayName: 'Vineet',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.categoryDao.upsert(
        CategoriesCompanion.insert(
          id: 'c1',
          householdId: 'h1',
          name: 'Food',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.expenseDao.upsert(
        ExpensesCompanion.insert(
          id: 'e1',
          householdId: 'h1',
          userId: 'u1',
          amountPaise: 1000,
          spentAt: now,
          spentOn: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      expect(await db.profileDao.findById('u1'), isNotNull);
      expect(await db.expenseDao.findById('e1'), isNotNull);

      await db.wipeAll();

      expect(await db.profileDao.findById('u1'), isNull);
      expect(await db.expenseDao.findById('e1'), isNull);
      expect(await db.categoryDao.watchAll('h1').first, isEmpty);
    },
  );
}
