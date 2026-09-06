import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/households_table.dart';

part 'household_dao.g.dart';

@DriftAccessor(tables: [Households])
class HouseholdDao extends DatabaseAccessor<AppDatabase>
    with _$HouseholdDaoMixin {
  HouseholdDao(super.db);

  Future<Household?> findById(String id) =>
      (select(households)..where((t) => t.id.equals(id))).getSingleOrNull();

  Stream<Household?> watchById(String id) =>
      (select(households)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsert(HouseholdsCompanion entry) =>
      into(households).insertOnConflictUpdate(entry);

  Future<void> markSynced(String id) =>
      (update(households)..where((t) => t.id.equals(id))).write(
        const HouseholdsCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  /// Like [markSynced], but also stamps the compare-and-swap base to
  /// [baseUpdatedAt] (the value this device just successfully pushed) —
  /// used by `pushUpsert`'s conflict-resolution path (see docs/DECISIONS.md,
  /// Gate 4 2026-09-05 fix).
  Future<void> markSyncedWithBase(String id, String baseUpdatedAt) =>
      (update(households)..where((t) => t.id.equals(id))).write(
        HouseholdsCompanion(
          isDirty: const Value(false),
          syncStatus: const Value('synced'),
          baseUpdatedAt: Value(baseUpdatedAt),
        ),
      );

  /// Refreshes the compare-and-swap base to the server's current value
  /// without touching `isDirty`/`updatedAt` — used when a push conflict is
  /// resolved in favour of the (still-pending) local edit, so the next push
  /// attempt's compare-and-swap uses the up-to-date base.
  Future<void> updateBaseUpdatedAt(String id, String baseUpdatedAt) =>
      (update(households)..where((t) => t.id.equals(id))).write(
        HouseholdsCompanion(baseUpdatedAt: Value(baseUpdatedAt)),
      );
}
