import 'package:drift/drift.dart';

import '../../../core/db/app_database.dart';
import '../../../domain/models/income.dart' as domain;

extension IncomeRowMapper on Income {
  domain.Income toDomain() => domain.Income(
        id: id,
        householdId: householdId,
        userId: userId,
        amountPaise: amountPaise,
        categoryId: categoryId,
        receivedAt: receivedAt,
        receivedOn: receivedOn,
        note: note,
        source: source,
        recurringRuleId: recurringRuleId,
        occurrenceDate: occurrenceDate,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
      );
}

extension IncomeDomainMapper on domain.Income {
  IncomesCompanion toCompanion({bool dirty = false}) => IncomesCompanion(
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
        syncStatus: Value(dirty ? 'pending' : 'synced'),
      );
}
