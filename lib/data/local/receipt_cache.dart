import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/logging/app_logger.dart';

/// Deletes the local receipt image cache (spec §11.1 T-3.6, §9.6 rule 3).
/// Shared by sign-out and the sync engine's household-change wipe (T-M2.7) —
/// both treat "this device's local data no longer belongs to it" the same
/// way. Best-effort: a failure here must not block the caller's own wipe.
Future<void> clearReceiptCache() async {
  try {
    final dir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory(p.join(dir.path, AppConstants.receiptsCacheDir));
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
    }
  } catch (error, stackTrace) {
    AppLogger.instance.warn('Failed to clear receipt cache', error, stackTrace);
  }
}
