import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/sync/entity_sync_adapters.dart';
import 'package:kharcha/data/sync/pull_service.dart';

/// A minimal [EntitySyncAdapter] whose `selectSince` mimics the real
/// since-cursor + limit contract in memory, so [PullService]'s paging loop
/// and cursor advancement can be tested without a network call.
class FakePagingAdapter extends EntitySyncAdapter {
  FakePagingAdapter(this.entityKey, this.allRows);

  @override
  final String entityKey;
  final List<Map<String, dynamic>> allRows;

  final List<String> appliedIds = [];
  final List<DateTime> queriedCursors = [];

  @override
  bool get supportsPush => false;

  @override
  bool get hasTombstones => false;

  @override
  Future<List<Map<String, dynamic>>> selectSince({
    required String householdId,
    required DateTime cursor,
    required int limit,
  }) async {
    queriedCursors.add(cursor);
    final matching =
        allRows
            .where(
              (row) =>
                  DateTime.parse(row['updated_at'] as String).isAfter(cursor),
            )
            .toList()
          ..sort(
            (a, b) => (a['updated_at'] as String).compareTo(
              b['updated_at'] as String,
            ),
          );
    return matching.take(limit).toList();
  }

  @override
  Future<void> pullApply(AppDatabase db, Map<String, dynamic> json) async {
    appliedIds.add(json['id'] as String);
  }

  @override
  Future<void> pushUpsert(AppDatabase db, Map<String, dynamic> payload) =>
      throw UnimplementedError();

  @override
  Future<void> pushSoftDelete(String id, DateTime now) =>
      throw UnimplementedError();

  @override
  Future<void> markLocalSynced(AppDatabase db, String id) async {}
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('pages a 501-row pull across two requests and advances the cursor to the max updated_at', () async {
    final base = DateTime.utc(2026, 1, 1);
    final rows = [
      for (var i = 0; i < 501; i++)
        {
          'id': 'row_$i',
          'updated_at': base.add(Duration(seconds: i)).toIso8601String(),
        },
    ];
    final adapter = FakePagingAdapter('expense', rows);
    final service = PullService(db: db, adapters: [adapter]);

    await service.pullAll('household-1');

    expect(adapter.appliedIds, hasLength(501));
    expect(adapter.appliedIds.first, 'row_0');
    expect(adapter.appliedIds.last, 'row_500');
    expect(
      adapter.queriedCursors,
      hasLength(2),
    ); // 500 (== limit) then 1 (< limit) — loop stops after 2 pages

    final meta = await db.syncMetaDao.find('expense');
    expect(meta, isNotNull);
    // Drift returns DateTime columns flagged as local time even though the
    // stored instant is correct — normalise before comparing (`==` is
    // sensitive to the UTC/local flag; the instant itself is unaffected, as
    // proven by `.toUtc()` round-tripping back to the original value).
    expect(meta!.lastPulledAt!.toUtc(), base.add(const Duration(seconds: 500)));
  });

  test('an entity with zero remote rows leaves sync_meta untouched', () async {
    final adapter = FakePagingAdapter('income', const []);
    final service = PullService(db: db, adapters: [adapter]);

    await service.pullAll('household-1');

    expect(adapter.appliedIds, isEmpty);
    final meta = await db.syncMetaDao.find('income');
    expect(meta?.lastPulledAt, isNull);
  });

  test('pullEntity only pulls the named entity', () async {
    final base = DateTime.utc(2026, 1, 1);
    final expenseAdapter = FakePagingAdapter('expense', [
      {'id': 'e1', 'updated_at': base.toIso8601String()},
    ]);
    final incomeAdapter = FakePagingAdapter('income', [
      {'id': 'i1', 'updated_at': base.toIso8601String()},
    ]);
    final service = PullService(
      db: db,
      adapters: [expenseAdapter, incomeAdapter],
    );

    await service.pullEntity('income', 'household-1');

    expect(incomeAdapter.appliedIds, ['i1']);
    expect(expenseAdapter.appliedIds, isEmpty);
  });
}
