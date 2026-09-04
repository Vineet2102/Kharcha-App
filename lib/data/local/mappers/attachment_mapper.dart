import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/attachment.dart' as domain;

extension AttachmentRowMapper on Attachment {
  domain.Attachment toDomain() => domain.Attachment(
        id: id,
        householdId: householdId,
        expenseId: expenseId,
        storagePath: storagePath,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        widthPx: widthPx,
        heightPx: heightPx,
        uploadedBy: uploadedBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );
}

extension AttachmentDomainMapper on domain.Attachment {
  AttachmentsCompanion toCompanion({bool dirty = false}) => AttachmentsCompanion(
        id: Value(id),
        householdId: Value(householdId),
        expenseId: Value(expenseId),
        storagePath: Value(storagePath),
        mimeType: Value(mimeType),
        sizeBytes: Value(sizeBytes),
        widthPx: Value(widthPx),
        heightPx: Value(heightPx),
        uploadedBy: Value(uploadedBy),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
        isDirty: Value(dirty),
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
