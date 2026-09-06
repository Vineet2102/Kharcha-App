import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show consolidateHttpClientResponseBytes;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants/app_constants.dart';
import '../../core/db/app_database.dart';
import '../../core/db/database_provider.dart';
import '../../core/errors/failure.dart';
import '../../core/result/result.dart';
import '../../domain/models/attachment.dart' as domain;
import '../local/mappers/attachment_mapper.dart';
import '../remote/supabase_client_provider.dart';
import '../sync/sync_engine.dart';
import 'expense_repository.dart';

part 'attachment_repository.g.dart';

const _uuid = Uuid();

/// Compresses the image at [sourcePath], returning the compressed bytes (or
/// null if the plugin declines, e.g. an unsupported format) — injected so
/// tests can substitute a fake that doesn't need a platform channel. The
/// real implementation is [FlutterImageCompress.compressWithFile].
typedef ImageCompressor = Future<Uint8List?> Function(
  String sourcePath, {
  required int quality,
  required int minWidth,
  required int minHeight,
});

Future<Uint8List?> _defaultCompressor(
  String sourcePath, {
  required int quality,
  required int minWidth,
  required int minHeight,
}) => FlutterImageCompress.compressWithFile(
  sourcePath,
  quality: quality,
  minWidth: minWidth,
  minHeight: minHeight,
);

/// Receipt photo capture/storage (spec §11.9, T-10.1–T-10.5). Follows the
/// same local-first + outbox shape as every other repository, plus two
/// things unique to attachments:
///  - the actual image bytes live in the local cache dir / Supabase Storage,
///    not in a Drift column, so this repository (unlike the others) talks to
///    the Supabase client directly for the download path — the "iron rule"
///    (§9.1) is about *entity data*, which is still Drift+outbox only.
///  - it keeps the `expenses.has_receipt` flag honest via
///    [ExpenseRepository.setHasReceipt].
class AttachmentRepository {
  AttachmentRepository(
    this._db,
    this._client,
    this._expenseRepository,
    this._triggerSync, {
    ImageCompressor? compressor,
  }) : _compressor = compressor ?? _defaultCompressor;

  final AppDatabase _db;
  final SupabaseClient _client;
  final ExpenseRepository _expenseRepository;
  final void Function() _triggerSync;
  final ImageCompressor _compressor;

  /// Spec §11.9.
  static const maxPerExpense = 3;

  Stream<List<domain.Attachment>> watchForExpense(String expenseId) => _db
      .attachmentDao
      .watchForExpense(expenseId)
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  Future<domain.Attachment?> findById(String id) async =>
      (await _db.attachmentDao.findById(id))?.toDomain();

  /// Compresses [sourcePath] (already picked via `image_picker` by the
  /// caller) to `<app-docs>/receipts/<id>.jpg`, inserts the `attachments`
  /// row, flips `has_receipt` on, and enqueues the upload outbox job (spec
  /// §11.9's capture pipeline). Enforces the max-3-per-expense limit.
  Future<Result<String, Failure>> addFromFile({
    required String householdId,
    required String expenseId,
    required String uploadedBy,
    required String sourcePath,
  }) async {
    final existing = await _db.attachmentDao.countForExpense(expenseId);
    if (existing >= maxPerExpense) {
      return const Result.err(
        ValidationFailure('An expense can have at most 3 receipt photos.'),
      );
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc();
    final cacheDir = await _receiptsCacheDir();
    final targetFile = File(p.join(cacheDir.path, '$id.jpg'));

    final compressed = await _compressor(
      sourcePath,
      quality: 80,
      minWidth: 1600,
      minHeight: 1600,
    );
    if (compressed != null) {
      await targetFile.writeAsBytes(compressed);
    } else {
      // Plugin declined (e.g. an already-tiny or unsupported source) — fall
      // back to the original bytes rather than losing the photo.
      await File(sourcePath).copy(targetFile.path);
    }
    final sizeBytes = await targetFile.length();
    final storagePath = '$householdId/$expenseId/$id.jpg';

    final attachment = domain.Attachment(
      id: id,
      householdId: householdId,
      expenseId: expenseId,
      storagePath: storagePath,
      sizeBytes: sizeBytes,
      uploadedBy: uploadedBy,
      createdAt: now,
      updatedAt: now,
    );

    await _db.attachmentDao.upsert(attachment.toCompanion(dirty: true));
    await _expenseRepository.setHasReceipt(expenseId, true);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'attachment',
        entityId: id,
        op: 'upload',
        payload: jsonEncode({
          'local_path': targetFile.path,
          'storage_path': storagePath,
          'row': attachment.toJson(),
        }),
        createdAt: now,
      ),
    );
    _triggerSync();
    return Result.ok(id);
  }

  /// Soft-deletes one attachment and enqueues its removal (row tombstone +
  /// best-effort Storage object delete, spec §11.9/T-10.5). Turns
  /// `has_receipt` back off if this was the expense's last receipt.
  Future<void> delete(String id) async {
    final row = await _db.attachmentDao.findById(id);
    if (row == null || row.deletedAt != null) return;
    final now = DateTime.now().toUtc();
    await _db.attachmentDao.softDelete(id, now);
    await _db.outboxDao.enqueue(
      OutboxEntriesCompanion.insert(
        id: _uuid.v4(),
        entity: 'attachment',
        entityId: id,
        op: 'delete',
        payload: '{}',
        createdAt: now,
      ),
    );
    final remaining = await _db.attachmentDao.countForExpense(row.expenseId);
    if (remaining == 0) {
      await _expenseRepository.setHasReceipt(row.expenseId, false);
    }
    _triggerSync();
  }

  /// Resolves [attachment]'s image to a local file, per spec §11.9's
  /// resolution order: local cache file → signed URL download → cache it.
  Future<File> resolveLocalFile(domain.Attachment attachment) async {
    final cacheDir = await _receiptsCacheDir();
    final file = File(p.join(cacheDir.path, '${attachment.id}.jpg'));
    if (await file.exists()) return file;

    // Spec §8: receipts are private; always a short-lived signed URL, never
    // a public one.
    final signedUrl = await _client.storage
        .from('receipts')
        .createSignedUrl(attachment.storagePath, 3600);
    final request = await HttpClient().getUrl(Uri.parse(signedUrl));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw const StorageFailure('Could not download the receipt photo.');
    }
    final bytes = await consolidateHttpClientResponseBytes(response);
    await file.writeAsBytes(bytes);
    return file;
  }

  Future<Directory> _receiptsCacheDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, AppConstants.receiptsCacheDir));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }
}

@Riverpod(keepAlive: true)
AttachmentRepository attachmentRepository(Ref ref) => AttachmentRepository(
  ref.watch(appDatabaseProvider),
  ref.watch(supabaseClientProvider),
  ref.watch(expenseRepositoryProvider),
  () => ref.read(syncEngineProvider).sync(),
);

/// Live receipt list for one expense — backs the thumbnail row on the
/// expense detail screen.
@riverpod
Stream<List<domain.Attachment>> attachmentsForExpense(
  Ref ref,
  String expenseId,
) => ref.watch(attachmentRepositoryProvider).watchForExpense(expenseId);
