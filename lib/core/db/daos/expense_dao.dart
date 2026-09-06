import 'package:drift/drift.dart';

import '../../../domain/models/expense_filter.dart';
import '../app_database.dart';
import '../tables/expenses_table.dart';

part 'expense_dao.g.dart';

@DriftAccessor(tables: [Expenses])
class ExpenseDao extends DatabaseAccessor<AppDatabase> with _$ExpenseDaoMixin {
  ExpenseDao(super.db);

  Stream<List<Expense>> watchAll(String householdId) {
    return (select(expenses)
          ..where(
            (t) => t.householdId.equals(householdId) & t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.spentOn)]))
        .watch();
  }

  /// Backs the Expense List's infinite scroll (spec §11.3): the top [limit]
  /// rows matching [filter], reverse-chronological. The caller grows [limit]
  /// by the page size (50) as the user scrolls, rather than this DAO
  /// tracking an offset — that keeps the stream correct if a row is
  /// inserted/edited/deleted anywhere in the already-loaded range, which a
  /// stale offset-based page wouldn't reliably do.
  Stream<List<Expense>> watchFiltered({
    required String householdId,
    required ExpenseFilter filter,
    required int limit,
  }) {
    return (select(expenses)
          ..where((t) => _filterExpression(t, householdId, filter))
          ..orderBy([
            (t) => OrderingTerm.desc(t.spentOn),
            (t) => OrderingTerm.desc(t.spentAt),
          ])
          ..limit(limit))
        .watch();
  }

  /// Every row matching [filter], unpaginated — the Export screen (spec
  /// §11.11, T-12.1) needs every matching expense, not a bounded page, and
  /// runs once on demand rather than staying subscribed.
  Future<List<Expense>> getFiltered({
    required String householdId,
    required ExpenseFilter filter,
  }) {
    return (select(expenses)
          ..where((t) => _filterExpression(t, householdId, filter))
          ..orderBy([
            (t) => OrderingTerm.desc(t.spentOn),
            (t) => OrderingTerm.desc(t.spentAt),
          ]))
        .get();
  }

  /// Sum of `amount_paise` for every row matching [filter] (not just the
  /// loaded page) — the Expense List header's "filtered total" (spec §11.3).
  Stream<int> watchFilteredTotal({
    required String householdId,
    required ExpenseFilter filter,
  }) {
    final query = selectOnly(expenses)
      ..addColumns([expenses.amountPaise.sum()])
      ..where(_filterExpression(expenses, householdId, filter));
    return query
        .map((row) => row.read(expenses.amountPaise.sum()) ?? 0)
        .watchSingle();
  }

  Expression<bool> _filterExpression(
    $ExpensesTable t,
    String householdId,
    ExpenseFilter filter,
  ) {
    Expression<bool> cond =
        t.householdId.equals(householdId) & t.deletedAt.isNull();
    if (filter.startDate != null) {
      cond = cond & t.spentOn.isBiggerOrEqualValue(filter.startDate!);
    }
    if (filter.endDate != null) {
      cond = cond & t.spentOn.isSmallerOrEqualValue(filter.endDate!);
    }
    if (filter.memberIds.isNotEmpty) {
      cond = cond & t.userId.isIn(filter.memberIds);
    }
    if (filter.categoryIds.isNotEmpty) {
      cond = cond & t.categoryId.isIn(filter.categoryIds);
    }
    if (filter.paymentMethodIds.isNotEmpty) {
      cond = cond & t.paymentMethodId.isIn(filter.paymentMethodIds);
    }
    if (filter.minAmountPaise != null) {
      cond = cond & t.amountPaise.isBiggerOrEqualValue(filter.minAmountPaise!);
    }
    if (filter.maxAmountPaise != null) {
      cond = cond & t.amountPaise.isSmallerOrEqualValue(filter.maxAmountPaise!);
    }
    if (filter.onlyWithReceipts) {
      cond = cond & t.hasReceipt.equals(true);
    }
    final search = filter.searchText.trim();
    if (search.isNotEmpty) {
      final like = '%$search%';
      cond = cond & (t.note.like(like) | t.merchant.like(like));
    }
    return cond;
  }

  /// Spec §11.2's duplicate guard: another non-deleted expense by the same
  /// user, same amount and category, within 2 minutes of [spentAt].
  Future<bool> hasPossibleDuplicate({
    required String householdId,
    required String userId,
    required int amountPaise,
    required String? categoryId,
    required DateTime spentAt,
    String? excludingId,
  }) async {
    final windowStart = spentAt.subtract(const Duration(minutes: 2));
    final windowEnd = spentAt.add(const Duration(minutes: 2));
    final query = select(expenses)
      ..where((t) {
        Expression<bool> cond =
            t.householdId.equals(householdId) &
            t.userId.equals(userId) &
            t.amountPaise.equals(amountPaise) &
            t.deletedAt.isNull() &
            t.spentAt.isBiggerOrEqualValue(windowStart) &
            t.spentAt.isSmallerOrEqualValue(windowEnd);
        cond =
            cond &
            (categoryId == null
                ? t.categoryId.isNull()
                : t.categoryId.equals(categoryId));
        if (excludingId != null) cond = cond & t.id.equals(excludingId).not();
        return cond;
      })
      ..limit(1);
    final rows = await query.get();
    return rows.isNotEmpty;
  }

  /// The most recently used payment method for [userId] — the Add Expense
  /// form's default (spec §11.2).
  Future<String?> lastUsedPaymentMethodId(String userId) async {
    final row =
        await (select(expenses)
              ..where((t) => t.userId.equals(userId) & t.deletedAt.isNull())
              ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.paymentMethodId;
  }

  /// Up to 8 category ids this user has used most often, most-used first —
  /// the Add Expense form's chip row (spec §11.2).
  Future<List<String>> mostUsedCategoryIds(
    String userId, {
    int limit = 8,
  }) async {
    final countExpr = expenses.id.count();
    final query = selectOnly(expenses)
      ..addColumns([expenses.categoryId, countExpr])
      ..where(
        expenses.userId.equals(userId) &
            expenses.deletedAt.isNull() &
            expenses.categoryId.isNotNull(),
      )
      ..groupBy([expenses.categoryId])
      ..orderBy([OrderingTerm.desc(countExpr)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map((r) => r.read(expenses.categoryId)!).toList();
  }

  /// Up to [limit] most-recent distinct, non-empty notes/merchants by
  /// [userId] — autocomplete sources for the Add Expense form (spec §11.2).
  /// Recency order can't be expressed with a plain SQL `DISTINCT`, so this
  /// over-fetches a recent window and dedupes in Dart, which is cheap at the
  /// row counts involved here.
  Future<List<String>> recentDistinctNotes(String userId, {int limit = 20}) =>
      _recentDistinctValues(
        userId: userId,
        limit: limit,
        matches: (t) => t.note.isNotValue(''),
        valueOf: (row) => row.note,
      );

  Future<List<String>> recentDistinctMerchants(
    String userId, {
    int limit = 20,
  }) => _recentDistinctValues(
    userId: userId,
    limit: limit,
    matches: (t) => t.merchant.isNotValue(''),
    valueOf: (row) => row.merchant,
  );

  Future<List<String>> _recentDistinctValues({
    required String userId,
    required int limit,
    required Expression<bool> Function($ExpensesTable t) matches,
    required String Function(Expense row) valueOf,
  }) async {
    final query = select(expenses)
      ..where(
        (t) => t.userId.equals(userId) & t.deletedAt.isNull() & matches(t),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
      ..limit(200);
    final rows = await query.get();
    final seen = <String>{};
    final result = <String>[];
    for (final row in rows) {
      final value = valueOf(row);
      if (value.isEmpty || !seen.add(value)) continue;
      result.add(value);
      if (result.length == limit) break;
    }
    return result;
  }

  /// Whether the household logged at least one (non-deleted) expense on
  /// [calendarDate] — backs the daily-logging-reminder's "skip if the user
  /// already logged ≥ 1 expense today" rule (spec §11.12, T-13.2).
  Future<bool> hasAnyOn(String householdId, DateTime calendarDate) async {
    final query = selectOnly(expenses)
      ..addColumns([expenses.id.count()])
      ..where(
        expenses.householdId.equals(householdId) &
            expenses.deletedAt.isNull() &
            expenses.spentOn.equals(calendarDate),
      );
    final row = await query.getSingle();
    return (row.read(expenses.id.count()) ?? 0) > 0;
  }

  Future<Expense?> findById(String id) =>
      (select(expenses)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// The already-posted expense for one recurring occurrence, if any —
  /// mirrors the server's `expenses_recurrence_unique` index and guards the
  /// posting engine (spec §11.8, T-9.3/T-9.4) against re-creating an
  /// occurrence it already posted locally (e.g. after a crash between
  /// creating the row and advancing `next_due_date`).
  Future<Expense?> findByOccurrence(
    String recurringRuleId,
    DateTime occurrenceDate,
  ) =>
      (select(expenses)..where(
            (t) =>
                t.recurringRuleId.equals(recurringRuleId) &
                t.occurrenceDate.equals(occurrenceDate) &
                t.deletedAt.isNull(),
          ))
          .getSingleOrNull();

  Stream<Expense?> watchById(String id) =>
      (select(expenses)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<void> upsert(ExpensesCompanion entry) =>
      into(expenses).insertOnConflictUpdate(entry);

  Future<void> softDelete(String id, DateTime now) =>
      (update(expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          localUpdatedAt: Value(now),
          isDirty: const Value(true),
          syncStatus: const Value('pending'),
        ),
      );

  Future<void> markSynced(String id) =>
      (update(expenses)..where((t) => t.id.equals(id))).write(
        const ExpensesCompanion(
          isDirty: Value(false),
          syncStatus: Value('synced'),
        ),
      );

  /// See `CategoryDao.markSyncedWithBase`.
  Future<void> markSyncedWithBase(String id, String baseUpdatedAt) =>
      (update(expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(
          isDirty: const Value(false),
          syncStatus: const Value('synced'),
          baseUpdatedAt: Value(baseUpdatedAt),
        ),
      );

  /// See `CategoryDao.updateBaseUpdatedAt`.
  Future<void> updateBaseUpdatedAt(String id, String baseUpdatedAt) =>
      (update(expenses)..where((t) => t.id.equals(id))).write(
        ExpensesCompanion(baseUpdatedAt: Value(baseUpdatedAt)),
      );

  Future<int> hardDelete(String id) =>
      (delete(expenses)..where((t) => t.id.equals(id))).go();

  /// Used by the category/payment-method delete guard (spec §11.5): a
  /// non-deleted expense still referencing the id blocks a hard/soft delete
  /// in favour of "Archive instead".
  Future<int> countByCategory(String categoryId) => _countWhere(
    (t) => t.categoryId.equals(categoryId) & t.deletedAt.isNull(),
  );

  Future<int> countByPaymentMethod(String paymentMethodId) => _countWhere(
    (t) => t.paymentMethodId.equals(paymentMethodId) & t.deletedAt.isNull(),
  );

  Future<int> _countWhere(
    Expression<bool> Function($ExpensesTable t) pred,
  ) async {
    final query = selectOnly(expenses)
      ..addColumns([expenses.id.count()])
      ..where(pred(expenses));
    final row = await query.getSingle();
    return row.read(expenses.id.count()) ?? 0;
  }
}
