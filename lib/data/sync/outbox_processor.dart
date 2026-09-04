import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/error_mapper.dart';
import '../../core/errors/failure.dart';
import '../../core/logging/app_logger.dart';
import '../remote/supabase_client_provider.dart';
import 'backoff.dart';
import 'entity_sync_adapters.dart';

part 'outbox_processor.g.dart';

/// Push side of the sync engine (spec §9.6 pushOutbox(), T-4.3): drains the
/// outbox FIFO, in dependency order, dispatching each entry to the matching
/// [EntitySyncAdapter]. A permanent failure (RLS denial, constraint
/// violation) is parked with `status='failed'`; a transient one (network,
/// 5xx, timeout) gets an exponential backoff retry.
class OutboxProcessor {
  OutboxProcessor({
    required this.db,
    required this.client,
    required this.adaptersByKey,
    Random? random,
  }) : _random = random ?? Random();

  final AppDatabase db;
  final SupabaseClient client;
  final Map<String, EntitySyncAdapter> adaptersByKey;
  final Random _random;

  /// `category`/`payment_method` before `expense`/`income`/`budget`/
  /// `recurring_rule`; `expense` before `attachment` (spec §9.6). Entries
  /// keep FIFO order *within* an entity because `OutboxDao.dueEntries()`
  /// already returns them sorted by `created_at`.
  static const dependencyOrder = [
    'household',
    'profile',
    'category',
    'payment_method',
    'expense',
    'income',
    'budget',
    'recurring_rule',
    'attachment',
  ];

  Future<void> process() async {
    final now = DateTime.now().toUtc();
    final due = await db.outboxDao.dueEntries(now);
    for (final entry in _orderByDependency(due)) {
      await _processEntry(entry, now);
    }
  }

  List<OutboxEntry> _orderByDependency(List<OutboxEntry> entries) {
    final byEntity = <String, List<OutboxEntry>>{};
    for (final entry in entries) {
      (byEntity[entry.entity] ??= []).add(entry);
    }
    final ordered = <OutboxEntry>[
      for (final key in dependencyOrder) ...?byEntity.remove(key),
    ];
    // Any entity outside the known list (shouldn't happen) still gets pushed.
    for (final rest in byEntity.values) {
      ordered.addAll(rest);
    }
    return ordered;
  }

  Future<void> _processEntry(OutboxEntry entry, DateTime now) async {
    final adapter = adaptersByKey[entry.entity];
    if (adapter == null) {
      await db.outboxDao.markFailed(
        entry.id,
        'Unknown outbox entity: ${entry.entity}',
      );
      return;
    }
    try {
      switch (entry.op) {
        case 'upsert':
          await adapter.pushUpsert(
            jsonDecode(entry.payload) as Map<String, dynamic>,
          );
        case 'delete':
          await adapter.pushSoftDelete(entry.entityId, now);
        case 'upload':
          await _processUpload(adapter, entry);
        default:
          throw StateError('Unknown outbox op: ${entry.op}');
      }
      await db.outboxDao.remove(entry.id);
      await adapter.markLocalSynced(db, entry.entityId);
    } catch (error, stackTrace) {
      await _handleFailure(entry, error, stackTrace);
    }
  }

  /// Uploads the cached receipt image, then upserts the `attachments` row
  /// (spec §9.6: "upload the cached image file to Storage, then upsert the
  /// attachments row"). Nothing enqueues an `upload` op until Phase 10
  /// builds the receipt-capture flow — this exists now for structural
  /// completeness of the outbox dispatch table.
  Future<void> _processUpload(
    EntitySyncAdapter adapter,
    OutboxEntry entry,
  ) async {
    final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
    final localPath = payload['local_path'] as String;
    final storagePath = payload['storage_path'] as String;
    final row = Map<String, dynamic>.from(payload['row'] as Map);
    await client.storage.from('receipts').upload(storagePath, File(localPath));
    await adapter.pushUpsert(row);
  }

  Future<void> _handleFailure(
    OutboxEntry entry,
    Object error,
    StackTrace stackTrace,
  ) async {
    AppLogger.instance.warn(
      'Outbox push failed for ${entry.entity}/${entry.entityId}',
      error,
      stackTrace,
    );
    final failure = ErrorMapper.map(error);
    final permanent =
        failure is PermissionFailure || failure is ValidationFailure;
    if (permanent) {
      await db.outboxDao.markFailed(entry.id, failure.message);
      return;
    }
    final attempts = entry.attempts + 1;
    await db.outboxDao.recordAttempt(
      entry.id,
      attempts: attempts,
      error: failure.message,
      nextAttemptAt: DateTime.now().toUtc().add(
        computeBackoff(attempts, random: _random),
      ),
    );
  }
}

@Riverpod(keepAlive: true)
OutboxProcessor outboxProcessor(Ref ref) => OutboxProcessor(
  db: ref.watch(appDatabaseProvider),
  client: ref.watch(supabaseClientProvider),
  adaptersByKey: ref.watch(entitySyncAdaptersByKeyProvider),
);
