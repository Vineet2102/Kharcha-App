import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../data/repositories/household_repository.dart';

part 'create_household_controller.g.dart';

/// Drives the "Create a household" screen (spec F-15, T-M2.6). `state` holds
/// the outcome (household id/name/invite code) once creation succeeds, so
/// the screen can flip from the name form to the invite-code reveal without
/// losing it across rebuilds.
///
/// `keepAlive: true` for the same reason as `SignUpController`/
/// `LoginController`: `createHousehold()` triggers a sync the instant it
/// succeeds (`HouseholdRepository`, T-M2.7), which can fire router redirects
/// mid-`await` — an auto-dispose provider would already be torn down by the
/// time this method's final `state = ...` runs.
@Riverpod(keepAlive: true)
class CreateHouseholdController extends _$CreateHouseholdController {
  @override
  FutureOr<CreateHouseholdOutcome?> build() => null;

  Future<bool> create(String name) async {
    state = const AsyncLoading();
    final result = await ref
        .read(householdRepositoryProvider)
        .createHousehold(name);
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
