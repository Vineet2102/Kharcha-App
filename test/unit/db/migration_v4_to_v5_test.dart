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

/// Regression test for Phase 14 (T-14.2/T-14.3): `household`/`profile`
/// gain push support, which needs the same `base_updated_at` CAS column
/// every other push-capable table already has. This exercises the actual
/// v4 -> v5 upgrade against a hand-built v4 file (rather than an in-memory
/// `AppDatabase.forTesting`, which always starts fresh at the latest
/// version) to prove existing family data — including a household name a
/// member had already edited offline before this upgrade shipped — survives
/// the new column being added.
void main() {
  late Directory tempDir;
  late String dbPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kharcha_migration_v5_test');
    dbPath = p.join(tempDir.path, 'kharcha.sqlite');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test(
    'upgrading a real v4 database backfills base_updated_at for a clean '
    'household/profile row and leaves it null for a still-dirty one, '
    'without losing any data',
    () async {
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
          is_dirty INTEGER NOT NULL DEFAULT 0
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
          is_dirty INTEGER NOT NULL DEFAULT 0
        );
      ''');
      // The 7 already-push-capable tables only need enough of the v4 shape
      // for the migration's (no-op, for them) upgrade path to open at all.
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
      final cleanUpdatedAt =
          DateTime.utc(2026, 1, 1).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO households (id, name, created_at, updated_at, is_dirty) '
        "VALUES ('hh1', 'Panicker Family', ?, ?, 0)",
        [cleanUpdatedAt, cleanUpdatedAt],
      );
      final dirtyUpdatedAt =
          DateTime.utc(2026, 1, 2).millisecondsSinceEpoch ~/ 1000;
      raw.execute(
        'INSERT INTO profiles '
        '(id, household_id, display_name, created_at, updated_at, is_dirty) '
        "VALUES ('u1', 'hh1', 'Vineet (edited)', ?, ?, 1)",
        [dirtyUpdatedAt, dirtyUpdatedAt],
      );
      raw.execute('PRAGMA user_version = 4;');
      raw.close();

      PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
      final db = AppDatabase();
      // Any query forces drift to open the file and run onUpgrade.
      final households = await db.select(db.households).get();
      final profiles = await db.select(db.profiles).get();
      expect(households, hasLength(1));
      expect(profiles, hasLength(1));

      expect(households.single.name, 'Panicker Family');
      expect(
        households.single.baseUpdatedAt,
        isNotNull,
        reason: 'a clean row backfills its base from its own updated_at',
      );

      expect(profiles.single.displayName, 'Vineet (edited)');
      expect(
        profiles.single.baseUpdatedAt,
        isNull,
        reason:
            "a dirty row's updated_at is its own unpushed edit, not a "
            'confirmed server value, so the backfill leaves it null — it '
            'falls back to an unconditional push once, then self-heals',
      );

      await db.close();
    },
  );
}
