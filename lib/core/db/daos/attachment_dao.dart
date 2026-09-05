import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/attachments_table.dart';

part 'attachment_dao.g.dart';

@DriftAccessor(tables: [Attachments])
class AttachmentDao extends DatabaseAccessor<AppDatabase>
    with _$AttachmentDaoMixin {
  AttachmentDao(super.db);

  Stream<List<Attachment>> watchForExpense(String expenseId) {
    return (select(attachments)
          ..where((t) => t.expenseId.equals(expenseId) & t.deletedAt.isNull()))
        .watch();
  }

  Future<Attachment?> findById(String id) =>
      (select(attachments)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<void> upsert(AttachmentsCompanion entry) =>
      into(attachments).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(attachments)..where((t) => t.id.equals(id))).write(
        AttachmentsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(attachments)..where((t) => t.id.equals(id))).write(
        const AttachmentsCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  /// See `CategoryDao.markSyncedWithBase`.
  Future<void> markSyncedWithBase(String id, DateTime baseUpdatedAt) =>
      (update(attachments)..where((t) => t.id.equals(id))).write(
        AttachmentsCompanion(
          isDirty: const Value(false),
          syncStatus: const Value('synced'),
          baseUpdatedAt: Value(baseUpdatedAt),
        ),
      );

  /// See `CategoryDao.updateBaseUpdatedAt`.
  Future<void> updateBaseUpdatedAt(String id, DateTime baseUpdatedAt) =>
      (update(attachments)..where((t) => t.id.equals(id))).write(
        AttachmentsCompanion(baseUpdatedAt: Value(baseUpdatedAt)),
      );

  Future<int> hardDelete(String id) =>
      (delete(attachments)..where((t) => t.id.equals(id))).go();
}
