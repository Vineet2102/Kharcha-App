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

/// Regression test for Phase M2 (T-M2.9): `profiles` gains `joined_at`,
/// mirroring a server column that existed since T-M1.1 but was never wired
/// into the local mirror. This exercises the actual v6 -> v7 upgrade against
/// a hand-built v6 file to prove existing member data survives the plain
/// column add.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kharcha_migration_v7_test');
    dbPath = p.join(tempDir.path, 'kharcha.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('upgrading a real v6 database adds joined_at (null for existing rows) '
      "without losing a member's other data", () async {
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
          last_success_at INTEGER NULL,
          household_id TEXT NULL
        );
      ''');
    final now = DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
    raw.execute(
      "INSERT INTO households (id, name, created_at, updated_at) "
      "VALUES ('hh1', 'Panicker Family', ?, ?)",
      [now, now],
    );
    raw.execute(
      'INSERT INTO profiles '
      '(id, household_id, display_name, role, created_at, updated_at) '
      "VALUES ('u1', 'hh1', 'Vineet', 'admin', ?, ?)",
      [now, now],
    );
    raw.execute('PRAGMA user_version = 6;');
    raw.close();

    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
    final db = AppDatabase();
    final profiles = await db.select(db.profiles).get();

    expect(profiles, hasLength(1));
    expect(profiles.single.displayName, 'Vineet');
    expect(profiles.single.role, 'admin');
    expect(
      profiles.single.joinedAt,
      isNull,
      reason:
          'a plain column add — existing rows read back null until their '
          'next pull refreshes them with the real server value',
    );

    await db.close();
  });
}
