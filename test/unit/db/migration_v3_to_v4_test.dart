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

/// Regression test for the Gate 10 fix (docs/DECISIONS.md, 2026-09-05):
/// devices that already ran the Gate 4 fix have a real on-disk v3 database
/// with `base_updated_at` as a lossy unix-seconds INTEGER column. This
/// exercises the actual v3 -> v4 upgrade against a hand-built v3 file
/// (rather than an in-memory `AppDatabase.forTesting`, which always starts
/// fresh at the latest version) to prove existing family data survives the
/// column being dropped and re-added as TEXT.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kharcha_migration_v4_test');
    dbPath = p.join(tempDir.path, 'kharcha.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrading a real v3 database drops the lossy INTEGER base_updated_at '
    'and re-adds it as TEXT, resetting every row to null without losing '
    'any other data',
    () async {
      // Build a v3-shaped categories table by hand: the exact columns
      // Gate 4's fix shipped, with base_updated_at still the lossy
      // unix-seconds INTEGER this fix replaces.
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
          base_updated_at INTEGER NULL,
          PRIMARY KEY (id)
        );
      ''');
      // The other 6 push-capable tables only need enough of the v3 shape
      // for the migration's ALTER statements to succeed — this test
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
            is_dirty INTEGER NOT NULL DEFAULT 0,
            base_updated_at INTEGER NULL
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
      // A row with a populated (lossy) base_updated_at, exactly what Gate
      // 4's own backfill would have produced for a clean row.
      final syncedAt = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO categories '
        '(id, household_id, name, created_at, updated_at, is_dirty, base_updated_at) '
        "VALUES ('clean1', 'hh1', 'Groceries', ?, ?, 0, ?)",
        [syncedAt, syncedAt, syncedAt],
      );
      raw.execute('PRAGMA user_version = 3;');
      raw.close();

      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      final db = AppDatabase();
      // Any query forces drift to open the file and run onUpgrade.
      final rows = await db.select(db.categories).get();
      expect(rows, hasLength(1));

      final row = rows.single;
      expect(row.name, 'Groceries', reason: 'existing data must survive');
      expect(
        row.baseUpdatedAt,
        isNull,
        reason:
            'the old lossy value is discarded, not migrated across — it '
            'could never CAS-match the server\'s full-precision updated_at '
            'anyway, so keeping it would just perpetuate the bug this fix '
            'closes. The next push for this row is unconditional once, '
            'then self-heals with a precise TEXT base.',
      );

      await db.close();
    },
  );
}
