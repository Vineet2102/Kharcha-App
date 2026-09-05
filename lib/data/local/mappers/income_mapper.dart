import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/income.dart' as domain;

extension IncomeRowMapper on Income {
  /// `.toUtc()` on every DateTime: Drift decodes a stored instant with
  /// `isUtc: false` even though it was written as UTC (see
  /// `docs/DECISIONS.md`, Phase 4's pull_service.dart fix).
  domain.Income toDomain() => domain.Income(
    id: id,
    householdId: householdId,
    userId: userId,
    amountPaise: amountPaise,
    categoryId: categoryId,
    receivedAt: receivedAt.toUtc(),
    receivedOn: receivedOn.toUtc(),
    note: note,
    source: source,
    recurringRuleId: recurringRuleId,
    occurrenceDate: occurrenceDate?.toUtc(),
    createdAt: createdAt.toUtc(),
    updatedAt: updatedAt.toUtc(),
    deletedAt: deletedAt?.toUtc(),
  );
}

extension IncomeDomainMapper on domain.Income {
  IncomesCompanion toCompanion({bool dirty = false, DateTime? baseUpdatedAt}) =>
      IncomesCompanion(
        id: Value(id),
        householdId: Value(householdId),
        userId: Value(userId),
        amountPaise: Value(amountPaise),
        categoryId: Value(categoryId),
        receivedAt: Value(receivedAt),
        receivedOn: Value(receivedOn),
        note: Value(note),
        source: Value(source),
        recurringRuleId: Value(recurringRuleId),
        occurrenceDate: Value(occurrenceDate),
        createdAt: Value(createdAt),
        updatedAt: Value(updatedAt),
        deletedAt: Value(deletedAt),
        isDirty: Value(dirty),
        localUpdatedAt: dirty
            ? Value(DateTime.now().toUtc())
            : const Value.absent(),
        syncStatus: Value(dirty ? 'pending' : 'synced'),
        baseUpdatedAt: baseUpdatedAt == null
            ? const Value.absent()
            : Value(baseUpdatedAt),
      );
}
