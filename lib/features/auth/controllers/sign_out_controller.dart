import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/db/database_provider.dart';
import '../../../core/errors/failure.dart';
import '../../../core/logging/app_logger.dart';
import '../../../core/result/result.dart';
import '../../../data/repositories/auth_repository.dart';

part 'sign_out_controller.g.dart';

/// Signs the current member out and wipes everything they can see on this
/// phone (spec §11.1, T-3.6): "On sign-out: wipe the local Drift database and
/// the receipt cache". The wipe runs even if the network sign-out call fails
/// — Supabase already clears the local session before it tries to notify the
/// server, so an offline sign-out must still scrub the device.
///
/// `keepAlive: true` for the same reason as [LoginController]: the auth
/// repository's `signOut()` call flips the session to null, which fires the
/// router redirect (T-3.4) and unmounts the Settings screen this controller
/// was read from — while `wipeAll()` is still running. An auto-dispose
/// provider gets torn down right then, and `ref.read(appDatabaseProvider)`
/// throws into a disposed `Ref`, silently skipping the wipe.
@Riverpod(keepAlive: true)
class SignOutController extends _$SignOutController {
  @override
  FutureOr<void> build() {}

  Future<Result<void, Failure>> signOut() async {
    state = const AsyncLoading();
    final result = await ref.read(authRepositoryProvider).signOut();
    await ref.read(appDatabaseProvider).wipeAll();
    await _clearReceiptCache();
    state = const AsyncData(null);
    return result;
  }

  Future<void> _clearReceiptCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory(p.join(dir.path, AppConstants.receiptsCacheDir));
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (error, stackTrace) {
      AppLogger.instance.warn('Failed to clear receipt cache on sign-out', error, stackTrace);
    }
  }
}
