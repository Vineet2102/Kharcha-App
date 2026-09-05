import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/payment_methods_table.dart';

part 'payment_method_dao.g.dart';

@DriftAccessor(tables: [PaymentMethods])
class PaymentMethodDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentMethodDaoMixin {
  PaymentMethodDao(super.db);

  Stream<List<PaymentMethod>> watchAll(String householdId) {
    return (select(paymentMethods)
          ..where(
            (t) => t.householdId.equals(householdId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
        .watch();
  }

  Future<PaymentMethod?> findById(String id) =>
      (select(paymentMethods)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(PaymentMethodsCompanion entry) =>
      into(paymentMethods).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(paymentMethods)..where((t) => t.id.equals(id))).write(
        PaymentMethodsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(paymentMethods)..where((t) => t.id.equals(id))).write(
        const PaymentMethodsCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  /// See `CategoryDao.markSyncedWithBase`.
  Future<void> markSyncedWithBase(String id, DateTime baseUpdatedAt) =>
      (update(paymentMethods)..where((t) => t.id.equals(id))).write(
        PaymentMethodsCompanion(
          isDirty: const Value(false),
          syncStatus: const Value('synced'),
          baseUpdatedAt: Value(baseUpdatedAt),
        ),
      );

  /// See `CategoryDao.updateBaseUpdatedAt`.
  Future<void> updateBaseUpdatedAt(String id, DateTime baseUpdatedAt) =>
      (update(paymentMethods)..where((t) => t.id.equals(id))).write(
        PaymentMethodsCompanion(baseUpdatedAt: Value(baseUpdatedAt)),
      );

  Future<int> hardDelete(String id) =>
      (delete(paymentMethods)..where((t) => t.id.equals(id))).go();
}
