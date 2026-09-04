import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/errors/failure.dart';
import 'package:kharcha/data/repositories/payment_method_repository.dart';
import 'package:kharcha/domain/models/enums.dart';

void main() {
  late AppDatabase db;
  late PaymentMethodRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = PaymentMethodRepository(db, () {});
  });
  tearDown(() => db.close());

  test('create writes a payment method and enqueues an outbox upsert', () async {
    await repo.create(householdId: 'h1', name: 'HDFC UPI', type: PayMethodType.upi);

    final methods = await db.paymentMethodDao.watchAll('h1').first;
    expect(methods, hasLength(1));
    expect(methods.single.name, 'HDFC UPI');

    final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
    expect(outbox.single.entity, 'payment_method');
    expect(outbox.single.op, 'upsert');
  });

  test(
    'delete is blocked while a non-deleted expense uses the payment method',
    () async {
      await repo.create(householdId: 'h1', name: 'Cash', type: PayMethodType.cash);
      final id = (await db.paymentMethodDao.watchAll('h1').first).single.id;
      final now = DateTime.utc(2026, 9, 1);
      await db.expenseDao.upsert(
        ExpensesCompanion.insert(
          id: 'e1',
          householdId: 'h1',
          userId: 'u1',
          amountPaise: 1000,
          paymentMethodId: Value(id),
          spentAt: now,
          spentOn: now,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await repo.delete(id);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
    },
  );

  test('delete succeeds and soft-deletes once unused', () async {
    await repo.create(householdId: 'h1', name: 'Cash', type: PayMethodType.cash);
    final id = (await db.paymentMethodDao.watchAll('h1').first).single.id;

    final result = await repo.delete(id);

    expect(result.isOk, isTrue);
    final row = await db.paymentMethodDao.findById(id);
    expect(row!.deletedAt, isNotNull);
  });
}
