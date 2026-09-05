import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/attachment.dart' as domain;

extension AttachmentRowMapper on Attachment {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though the value was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix) — left uncorrected
  /// here, a domain model built from a local row would silently serialise
  /// with the wrong offset the next time it's pushed.
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
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    deletedAt: deletedAt?.toUtc(),
    isDirty: isDirty,
  );
}

extension AttachmentDomainMapper on domain.Attachment {
  AttachmentsCompanion toCompanion({
    bool dirty = false,
    DateTime? baseUpdatedAt,
  }) => AttachmentsCompanion(
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
    localUpdatedAt: dirty ? Value(DateTime.now().toUtc()) : const Value.absent(),
    syncStatus: Value(dirty ? 'pending' : 'synced'),
    baseUpdatedAt: baseUpdatedAt == null
        ? const Value.absent()
        : Value(baseUpdatedAt),
  );
}
