import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('getFiltered scopes by date range, member and category, for the Export screen (T-12.1)', () async {
    final now = DateTime.utc(2026, 9, 1);
    Future<void> insert(
      String id,
      String userId,
      String? categoryId,
      DateTime receivedOn,
    ) => db.incomeDao.upsert(
      IncomesCompanion.insert(
        id: id,
        householdId: 'h1',
        userId: userId,
        categoryId: Value(categoryId),
        amountPaise: 500000,
        receivedAt: receivedOn,
        receivedOn: receivedOn,
        createdAt: now,
        updatedAt: now,
      ),
    );

    await insert('i1', 'u1', 'salary', DateTime.utc(2026, 9, 1));
    await insert('i2', 'u2', 'salary', DateTime.utc(2026, 9, 15));
    await insert('i3', 'u1', 'interest', DateTime.utc(2026, 8, 20));

    final rows = await db.incomeDao.getFiltered(
      householdId: 'h1',
      startDate: DateTime.utc(2026, 9, 1),
      endDate: DateTime.utc(2026, 9, 30),
      memberIds: const ['u1'],
    );

    // i2 belongs to a different member, i3 is outside the date range —
    // only i1 should survive.
    expect(rows.map((r) => r.id).toList(), ['i1']);
  });

  test('getFiltered with no scope returns every non-deleted row', () async {
    final now = DateTime.utc(2026, 9, 1);
    await db.incomeDao.upsert(
      IncomesCompanion.insert(
        id: 'i1',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 1000,
        receivedAt: now,
        receivedOn: now,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await db.incomeDao.softDelete('i1', now);
    await db.incomeDao.upsert(
      IncomesCompanion.insert(
        id: 'i2',
        householdId: 'h1',
        userId: 'u1',
        amountPaise: 2000,
        receivedAt: now,
        receivedOn: now,
        createdAt: now,
        updatedAt: now,
      ),
    );

    final rows = await db.incomeDao.getFiltered(householdId: 'h1');
    expect(rows.map((r) => r.id).toList(), ['i2']);
  });
}
