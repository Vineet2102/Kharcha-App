import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../constants/app_constants.dart';
import 'daos/attachment_dao.dart';
import 'daos/budget_dao.dart';
import 'daos/category_dao.dart';
import 'daos/expense_dao.dart';
import 'daos/household_dao.dart';
import 'daos/income_dao.dart';
import 'daos/outbox_dao.dart';
import 'daos/payment_method_dao.dart';
import 'daos/profile_dao.dart';
import 'daos/recurring_dao.dart';
import 'daos/sync_meta_dao.dart';
import 'tables/attachments_table.dart';
import 'tables/budgets_table.dart';
import 'tables/categories_table.dart';
import 'tables/expenses_table.dart';
import 'tables/households_table.dart';
import 'tables/incomes_table.dart';
import 'tables/outbox_entries_table.dart';
import 'tables/payment_methods_table.dart';
import 'tables/profiles_table.dart';
import 'tables/recurring_rules_table.dart';
import 'tables/sync_meta_table.dart';

part 'app_database.g.dart';

/// The local SQLite mirror (spec §9.5). This is the source of truth for the
/// UI — every read is a Drift stream, every write goes here plus an outbox
/// row. Only the `SyncEngine` (Phase 4) touches Supabase directly.
@DriftDatabase(
  tables: [
    Households,
    Profiles,
    Categories,
    PaymentMethods,
    Expenses,
    Incomes,
    Attachments,
    Budgets,
    RecurringRules,
    OutboxEntries,
    SyncMeta,
  ],
  daos: [
    ExpenseDao,
    IncomeDao,
    CategoryDao,
    PaymentMethodDao,
    BudgetDao,
    RecurringDao,
    AttachmentDao,
    OutboxDao,
    SyncMetaDao,
    ProfileDao,
    HouseholdDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    // v1 -> v2 (Phase 4, T-4.3): OutboxEntries.status distinguishes a
    // permanently-failed entry from one still waiting on backoff.
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(outboxEntries, outboxEntries.status);
      }
    },
  );

  /// Deletes every row from every table. Used on sign-out (spec §11.1,
  /// T-3.6) so a shared phone never keeps another member's data around
  /// after they log out.
  Future<void> wipeAll() async {
    await transaction(() async {
      for (final table in allTables) {
        await delete(table).go();
      }
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, AppConstants.dbFileName));
    return NativeDatabase.createInBackground(file);
  });
}
