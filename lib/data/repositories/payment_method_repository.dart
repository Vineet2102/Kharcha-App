import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../domain/models/enums.dart';
import '../../domain/models/payment_method.dart' as domain;
import '../local/mappers/payment_method_mapper.dart';
import '../sync/sync_engine.dart';

part 'payment_method_repository.g.dart';

const _uuid = Uuid();

/// Mirrors [CategoryRepository]'s shape exactly (spec §11.5, T-5.1):
/// local-first read, admin-only write enforced by RLS (`pm_write`) and by
/// hiding the controls for members.
class PaymentMethodRepository {
  PaymentMethodRepository(this._db, this._triggerSync);

  final AppDatabase _db;
  final void Function() _triggerSync;

  Stream<List<domain.PaymentMethod>> watchAll(String householdId) => _db
      .paymentMethodDao
      .watchAll(householdId)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Future<domain.PaymentMethod?> findById(String id) async =>
      (await _db.paymentMethodDao.findById(id))?.toDomain();

  Future<void> create({
    required String householdId,
    required String name,
    required PayMethodType type,
    int sortOrder = 100,
  }) {
    final now = DateTime.now().toUtc();
    return _save(
      domain.PaymentMethod(
        id: _uuid.v4(),
        householdId: householdId,
        name: name,
        type: type,
        sortOrder: sortOrder,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> update(domain.PaymentMethod method) =>
      _save(method.copyWith(updatedAt: DateTime.now().toUtc()));

  Future<void> setArchived(String id, bool archived) async {
    final existing = await findById(id);
    if (existing == null) return;
    await update(existing.copyWith(isArchived: archived));
  }

  Future<void> reorder(List<domain.PaymentMethod> reordered) async {
    for (var i = 0; i < reordered.length; i++) {
      await _save(
        reordered[i].copyWith(
          sortOrder: (i + 1) * 10,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  Future<Result<void, Failure>> delete(String id) async {
    final usage = await _db.expenseDao.countByPaymentMethod(id);
    if (usage > 0) {
      return const Result.err(
        ValidationFailure(
          'This payment method is used by existing expenses — archive it instead.',
        ),
      );
    }
    final existing = await findById(id);
    if (existing == null) return const Result.ok(null);
    final now = DateTime.now().toUtc();
    await _db.paymentMethodDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'payment_method',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    _triggerSync();
    return const Result.ok(null);
  }

  Future<void> _save(domain.PaymentMethod method) async {
    await _db.paymentMethodDao.upsert(method.toCompanion(dirty: true));
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'payment_method',
        entityId: method.id,
        op: 'upsert',
        payload: jsonEncode(method.toJson()),
        createdAt: DateTime.now().toUtc(),
      ),
    );
    _triggerSync();
  }
}

@Riverpod(keepAlive: true)
PaymentMethodRepository paymentMethodRepository(Ref ref) =>
    PaymentMethodRepository(
      ref.watch(appDatabaseProvider),
      () => ref.read(syncEngineProvider).sync(),
    );

/// All payment methods (incl. archived), for the management screen and
/// every expense-form payment-method picker.
@Riverpod(keepAlive: true)
Stream<List<domain.PaymentMethod>> paymentMethods(Ref ref) => ref
    .watch(paymentMethodRepositoryProvider)
    .watchAll(AppConstants.seedHouseholdId);
