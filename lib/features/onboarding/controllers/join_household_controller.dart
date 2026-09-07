import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/household_repository.dart';

part 'join_household_controller.g.dart';

/// Drives the "Join a household" screen (spec F-15, T-M2.6). Same
/// `keepAlive: true` reasoning as `CreateHouseholdController` — `joinHousehold`
/// triggers a sync on success (T-M2.7), which can fire router redirects
/// mid-`await`.
@Riverpod(keepAlive: true)
class JoinHouseholdController extends _$JoinHouseholdController {
  @override
  FutureOr<JoinHouseholdOutcome?> build() => null;

  Future<bool> join(String code) async {
    state = const AsyncLoading();
    final result = await ref
        .read(householdRepositoryProvider)
        .joinHousehold(code);
    return result.fold(
      (outcome) {
        state = AsyncData(outcome);
        return true;
      },
      (failure) {
        state = AsyncError(failure, StackTrace.current);
        return false;
      },
    );
  }
}
