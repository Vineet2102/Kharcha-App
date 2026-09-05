import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'package:kharcha/core/db/app_database.dart';

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Regression test for the Gate 4 fix (docs/DECISIONS.md, 2026-09-05):
/// devices already running the pre-fix app have a real on-disk v2 database
/// with no `base_updated_at` column. This exercises the actual v2 -> v3
/// upgrade path against a hand-built v2 file (rather than an in-memory
/// `AppDatabase.forTesting`, which always starts fresh at the latest
/// version) to prove existing family data survives the upgrade instead of
/// asserting it in the abstract.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kharcha_migration_test');
    dbPath = p.join(tempDir.path, 'kharcha.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrading a real v2 database backfills base_updated_at for clean rows '
    'and leaves it null for a still-dirty row, without losing any data',
    () async {
      // Build a v2-shaped categories table by hand (the columns Phase 2
      // shipped, before this fix's baseUpdatedAt column existed) and seed
      // one already-synced row and one row with an unpushed local edit.
      final raw = sqlite3.sqlite3.open(dbPath);
      raw.execute('''
        CREATE TABLE categories (
          id TEXT NOT NULL,
          household_id TEXT NOT NULL,
          name TEXT NOT NULL,
          kind TEXT NOT NULL DEFAULT 'expense',
          icon_key TEXT NOT NULL DEFAULT 'category',
          colour_hex TEXT NOT NULL DEFAULT '#607D8B',
          sort_order INTEGER NOT NULL DEFAULT 100,
          is_archived INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          deleted_at INTEGER NULL,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          local_updated_at INTEGER NULL,
          is_dirty INTEGER NOT NULL DEFAULT 0,
          PRIMARY KEY (id)
        );
      ''');
      // The other 6 push-capable tables only need enough of the v2 shape
      // for the migration's ALTER/UPDATE statements to succeed — this test
      // focuses its data-preservation assertions on categories.
      for (final table in [
        'payment_methods',
        'expenses',
        'incomes',
        'budgets',
        'recurring_rules',
        'attachments',
      ]) {
        raw.execute('''
          CREATE TABLE $table (
            id TEXT NOT NULL PRIMARY KEY,
            updated_at INTEGER NOT NULL,
            is_dirty INTEGER NOT NULL DEFAULT 0
          );
        ''');
      }
      raw.execute('''
        CREATE TABLE outbox_entries (
          id TEXT NOT NULL,
          entity TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          op TEXT NOT NULL,
          payload TEXT NOT NULL,
          attempts INTEGER NOT NULL DEFAULT 0,
          last_error TEXT NULL,
          next_attempt_at INTEGER NULL,
          created_at INTEGER NOT NULL,
          status TEXT NOT NULL DEFAULT 'pending',
          PRIMARY KEY (id)
        );
      ''');
      // Drift's default DateTimeColumn storage is unix seconds, not
      // milliseconds.
      final cleanUpdatedAt =
          DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO categories (id, household_id, name, created_at, updated_at, is_dirty) '
        "VALUES ('clean1', 'hh1', 'Groceries', ?, ?, 0)",
        [cleanUpdatedAt, cleanUpdatedAt],
      );
      final dirtyUpdatedAt =
          DateTime.utc(2026, 1, 2).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO categories (id, household_id, name, created_at, updated_at, is_dirty) '
        "VALUES ('dirty1', 'hh1', 'Rent (edited)', ?, ?, 1)",
        [dirtyUpdatedAt, dirtyUpdatedAt],
      );
      raw.execute('PRAGMA user_version = 2;');
      raw.close();

      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      final db = AppDatabase();
      // Any query forces drift to open the file and run onUpgrade.
      final rows = await db.select(db.categories).get();
      expect(rows, hasLength(2));

      final clean = rows.firstWhere((r) => r.id == 'clean1');
      expect(clean.name, 'Groceries', reason: 'existing data must survive');
      expect(
        clean.baseUpdatedAt!.toUtc(),
        DateTime.utc(2026, 1, 1),
        reason: 'a clean row\'s updatedAt already matched the server',
      );

      final dirty = rows.firstWhere((r) => r.id == 'dirty1');
      expect(dirty.name, 'Rent (edited)');
      expect(
        dirty.baseUpdatedAt,
        isNull,
        reason:
            'a still-dirty row\'s updatedAt is its own unpushed edit, not '
            'a confirmed server value — falls back to a plain upsert once, '
            'then self-heals',
      );

      await db.close();
    },
  );
}
