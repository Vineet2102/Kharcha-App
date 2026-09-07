import 'dart:io';

import 'package:drift/drift.dart' show Variable;
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

/// Regression test for Phase M2 (T-M2.7/T-M2.14): `sync_meta` gains
/// `household_id` so the sync engine can detect a join/leave/switch and
/// wipe-and-refetch instead of reconciling one household's rows against
/// another's cursors. This exercises the actual v5 -> v6 upgrade against a
/// hand-built v5 file (rather than an in-memory `AppDatabase.forTesting`,
/// which always starts fresh at the latest version) to prove: (1) existing
/// household data is untouched, and (2) every pull cursor is reset — the
/// only way to force exactly one full refetch, since no pre-v6 install ever
/// recorded which household its cursors belonged to.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kharcha_migration_v6_test');
    dbPath = p.join(tempDir.path, 'kharcha.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('upgrading a real v5 database resets every sync_meta cursor but leaves '
      "the household's existing rows untouched", () async {
    final raw = sqlite3.sqlite3.open(dbPath);
    raw.execute('''
        CREATE TABLE households (
          id TEXT NOT NULL PRIMARY KEY,
          name TEXT NOT NULL,
          currency_code TEXT NOT NULL DEFAULT 'INR',
          timezone TEXT NOT NULL DEFAULT 'Asia/Kolkata',
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          local_updated_at INTEGER NULL,
          is_dirty INTEGER NOT NULL DEFAULT 0,
          base_updated_at TEXT NULL
        );
      ''');
    raw.execute('''
        CREATE TABLE profiles (
          id TEXT NOT NULL PRIMARY KEY,
          household_id TEXT NOT NULL,
          display_name TEXT NOT NULL,
          role TEXT NOT NULL DEFAULT 'member',
          colour_hex TEXT NOT NULL DEFAULT '#6750A4',
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          sync_status TEXT NOT NULL DEFAULT 'synced',
          local_updated_at INTEGER NULL,
          is_dirty INTEGER NOT NULL DEFAULT 0,
          base_updated_at TEXT NULL
        );
      ''');
    for (final table in [
      'categories',
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
            base_updated_at TEXT NULL
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
    raw.execute('''
        CREATE TABLE sync_meta (
          entity TEXT NOT NULL PRIMARY KEY,
          last_pulled_at INTEGER NULL,
          last_success_at INTEGER NULL
        );
      ''');
    final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
    raw.execute(
      "INSERT INTO households (id, name, created_at, updated_at) "
      "VALUES ('hh1', 'Panicker Family', ?, ?)",
      [now, now],
    );
    raw.execute("INSERT INTO expenses (id, updated_at) VALUES ('exp1', ?)", [
      now,
    ]);
    raw.execute(
      "INSERT INTO sync_meta (entity, last_pulled_at, last_success_at) "
      "VALUES ('expense', ?, ?)",
      [now, now],
    );
    raw.execute(
      "INSERT INTO sync_meta (entity, last_pulled_at, last_success_at) "
      "VALUES ('household', ?, ?)",
      [now, now],
    );
    raw.execute('PRAGMA user_version = 5;');
    raw.close();

    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final db = AppDatabase();
    final households = await db.select(db.households).get();
    // The `expenses` table's real schema has several other NOT NULL
    // columns this fixture doesn't bother reproducing (this test isn't
    // about expenses' own shape) — a raw count sidesteps Drift's full row
    // mapper while still proving the row itself wasn't dropped.
    final expenseCount = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM expenses WHERE id = ?',
          variables: [Variable('exp1')],
        )
        .getSingle();
    final syncMeta = await db.select(db.syncMeta).get();

    expect(
      households.single.name,
      'Panicker Family',
      reason: 'existing household data survives the upgrade untouched',
    );
    expect(
      expenseCount.read<int>('c'),
      1,
      reason: 'existing expense rows survive the upgrade untouched',
    );
    expect(
      syncMeta,
      isEmpty,
      reason:
          'every cursor is reset (not backfilled/guessed) so the next '
          'sync performs exactly one full pull and stamps the real '
          'household id itself',
    );

    await db.close();
  });
}
