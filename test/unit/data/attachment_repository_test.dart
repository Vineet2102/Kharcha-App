import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/core/errors/failure.dart';
import 'package:kharcha/data/repositories/attachment_repository.dart';
import 'package:kharcha/data/repositories/expense_repository.dart';
import 'package:kharcha/domain/models/expense_filter.dart' as domain;

class MockSupabaseClient extends Mock implements SupabaseClient {}

class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.dir);
  final String dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir;
}

/// Fake compressor that just returns the source bytes unchanged — the real
/// `flutter_image_compress` needs a platform channel unavailable in a plain
/// `flutter_test` run, so it's injected (see `AttachmentRepository`'s
/// `ImageCompressor` typedef) and substituted here.
Future<Uint8List?> _passthroughCompressor(
  String sourcePath, {
  required int quality,
  required int minWidth,
  required int minHeight,
}) async => File(sourcePath).readAsBytes();

void main() {
  late Directory tempDir;
  late Directory docsDir;
  late AppDatabase db;
  late MockSupabaseClient client;
  late ExpenseRepository expenseRepo;
  late AttachmentRepository repo;
  late String sourceImagePath;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('kharcha_attachment_test');
    docsDir = Directory(p.join(tempDir.path, 'docs'))..createSync();
    PathProviderPlatform.instance = _FakePathProvider(docsDir.path);

    sourceImagePath = p.join(tempDir.path, 'source.jpg');
    File(sourceImagePath).writeAsBytesSync(List.filled(1024, 1));

    db = AppDatabase.forTesting(NativeDatabase.memory());
    client = MockSupabaseClient();
    expenseRepo = ExpenseRepository(db, () {});
    repo = AttachmentRepository(
      db,
      client,
      expenseRepo,
      () {},
      compressor: _passthroughCompressor,
    );

    await expenseRepo.create(
      householdId: 'h1',
      userId: 'u1',
      amountPaise: 5000,
      categoryId: 'c1',
      paymentMethodId: 'pm1',
      spentAt: DateTime.now().toUtc(),
    );
  });

  tearDown(() {
    db.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<String> theExpenseId() async {
    final rows = await db.expenseDao.watchFiltered(
      householdId: 'h1',
      filter: const domain.ExpenseFilter(),
      limit: 10,
    ).first;
    return rows.single.id;
  }

  test(
    'addFromFile caches a compressed copy, inserts a dirty row, enqueues an '
    'upload, and flips has_receipt on',
    () async {
      final expenseId = await theExpenseId();

      final result = await repo.addFromFile(
        householdId: 'h1',
        expenseId: expenseId,
        uploadedBy: 'u1',
        sourcePath: sourceImagePath,
      );

      expect(result.isOk, isTrue);
      final id = result.valueOrNull!;

      final cachedFile = File(p.join(docsDir.path, 'receipts', '$id.jpg'));
      expect(cachedFile.existsSync(), isTrue);

      final row = await db.attachmentDao.findById(id);
      expect(row, isNotNull);
      expect(row!.isDirty, isTrue);
      expect(row.storagePath, 'h1/$expenseId/$id.jpg');

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      final uploadEntry = outbox.singleWhere((e) => e.entity == 'attachment');
      expect(uploadEntry.op, 'upload');
      final payload = jsonDecode(uploadEntry.payload) as Map<String, dynamic>;
      expect(payload['storage_path'], 'h1/$expenseId/$id.jpg');
      expect(payload['local_path'], cachedFile.path);

      final expense = await expenseRepo.findById(expenseId);
      expect(expense!.hasReceipt, isTrue);
    },
  );

  test('addFromFile rejects a 4th receipt on the same expense', () async {
    final expenseId = await theExpenseId();
    for (var i = 0; i < 3; i++) {
      final result = await repo.addFromFile(
        householdId: 'h1',
        expenseId: expenseId,
        uploadedBy: 'u1',
        sourcePath: sourceImagePath,
      );
      expect(result.isOk, isTrue);
    }

    final fourth = await repo.addFromFile(
      householdId: 'h1',
      expenseId: expenseId,
      uploadedBy: 'u1',
      sourcePath: sourceImagePath,
    );

    expect(fourth.isErr, isTrue);
    expect(fourth.failureOrNull, isA<ValidationFailure>());
    final count = await db.attachmentDao.countForExpense(expenseId);
    expect(count, 3);
  });

  test(
    'delete soft-deletes the attachment, enqueues its removal, and turns '
    'has_receipt back off once none remain',
    () async {
      final expenseId = await theExpenseId();
      final result = await repo.addFromFile(
        householdId: 'h1',
        expenseId: expenseId,
        uploadedBy: 'u1',
        sourcePath: sourceImagePath,
      );
      final id = result.valueOrNull!;

      await repo.delete(id);

      final row = await db.attachmentDao.findById(id);
      expect(row!.deletedAt, isNotNull);
      expect(row.isDirty, isTrue);

      final outbox = await db.outboxDao.dueEntries(DateTime.now().toUtc());
      final deleteEntry = outbox.singleWhere(
        (e) => e.entity == 'attachment' && e.op == 'delete',
      );
      expect(deleteEntry.entityId, id);

      final expense = await expenseRepo.findById(expenseId);
      expect(expense!.hasReceipt, isFalse);
    },
  );

  test(
    'delete leaves has_receipt on while another receipt still exists',
    () async {
      final expenseId = await theExpenseId();
      final first = await repo.addFromFile(
        householdId: 'h1',
        expenseId: expenseId,
        uploadedBy: 'u1',
        sourcePath: sourceImagePath,
      );
      await repo.addFromFile(
        householdId: 'h1',
        expenseId: expenseId,
        uploadedBy: 'u1',
        sourcePath: sourceImagePath,
      );

      await repo.delete(first.valueOrNull!);

      final expense = await expenseRepo.findById(expenseId);
      expect(expense!.hasReceipt, isTrue);
    },
  );

  test('resolveLocalFile returns the cached file without touching Storage', () async {
    final expenseId = await theExpenseId();
    final result = await repo.addFromFile(
      householdId: 'h1',
      expenseId: expenseId,
      uploadedBy: 'u1',
      sourcePath: sourceImagePath,
    );
    final attachment = await repo.findById(result.valueOrNull!);

    final file = await repo.resolveLocalFile(attachment!);

    expect(file.existsSync(), isTrue);
    verifyNever(() => client.storage);
  });
}
