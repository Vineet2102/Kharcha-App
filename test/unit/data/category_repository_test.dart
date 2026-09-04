import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/errors/failure.dart';
import 'package:kharcha/data/local/mappers/category_mapper.dart';
import 'package:kharcha/data/repositories/category_repository.dart';
import 'package:kharcha/domain/models/enums.dart';

void main() {
  late AppDatabase db;
  late CategoryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = CategoryRepository(db, () {});
  });
  tearDown(() => db.close());

  test('create writes a category and enqueues an outbox upsert', () async {
    await repo.create(
      householdId: 'h1',
      name: 'Groceries',
      kind: CategoryKind.expense,
      iconKey: 'shopping_cart',
      colourHex: '#4CAF50',
    );

    final categories = await db.categoryDao.watchAll('h1').first;
    expect(categories, hasLength(1));
    expect(categories.single.name, 'Groceries');
    expect(categories.single.isDirty, isTrue);

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox, hasLength(1));
    expect(outbox.single.entity, 'category');
    expect(outbox.single.op, 'upsert');
  });

  test('setArchived toggles isArchived', () async {
    await repo.create(
      householdId: 'h1',
      name: 'Groceries',
      kind: CategoryKind.expense,
      iconKey: 'shopping_cart',
      colourHex: '#4CAF50',
    );
    final id = (await db.categoryDao.watchAll('h1').first).single.id;

    await repo.setArchived(id, true);

    final category = await repo.findById(id);
    expect(category!.isArchived, isTrue);
  });

  test('reorder assigns sequential sort_order values, spaced by 10', () async {
    await repo.create(
      householdId: 'h1',
      name: 'A',
      kind: CategoryKind.expense,
      iconKey: 'category',
      colourHex: '#607D8B',
    );
    await repo.create(
      householdId: 'h1',
      name: 'B',
      kind: CategoryKind.expense,
      iconKey: 'category',
      colourHex: '#607D8B',
    );
    final rows = await db.categoryDao.watchAll('h1').first;
    final domainCategories = rows.map((r) => r.toDomain()).toList();

    // Reverse the order (B first, A second) and persist it.
    await repo.reorder(domainCategories.reversed.toList());

    final reordered = await db.categoryDao.watchAll('h1').first;
    expect(reordered.map((c) => c.name).toList(), ['B', 'A']);
    expect(reordered[0].sortOrder, 10);
    expect(reordered[1].sortOrder, 20);
  });

  test(
    'delete is blocked while a non-deleted expense uses the category',
    () async {
      await repo.create(
        householdId: 'h1',
        name: 'Groceries',
        kind: CategoryKind.expense,
        iconKey: 'shopping_cart',
        colourHex: '#4CAF50',
      );
      final id = (await db.categoryDao.watchAll('h1').first).single.id;
      final now = DateTime.utc(2026, 9, 1);
      await db.expenseDao.upsert(
        ExpensesCompanion.insert(
          id: 'e1',
          householdId: 'h1',
          userId: 'u1',
          amountPaise: 1000,
          categoryId: Value(id),
          spentAt: now,
          spentOn: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await repo.delete(id);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
      final category = await repo.findById(id);
      expect(category, isNotNull, reason: 'not deleted');
    },
  );

  test('delete succeeds and soft-deletes once unused', () async {
    await repo.create(
      householdId: 'h1',
      name: 'Groceries',
      kind: CategoryKind.expense,
      iconKey: 'shopping_cart',
      colourHex: '#4CAF50',
    );
    final id = (await db.categoryDao.watchAll('h1').first).single.id;

    final result = await repo.delete(id);

    expect(result.isOk, isTrue);
    final row = await db.categoryDao.findById(id);
    expect(row!.deletedAt, isNotNull);
  });
}
