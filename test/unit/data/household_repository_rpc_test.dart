import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kharcha/core/db/app_database.dart';
import 'package:kharcha/data/remote/household_remote_ds.dart';
import 'package:kharcha/data/repositories/household_repository.dart';
import 'package:kharcha/domain/models/enums.dart';

class MockHouseholdRemoteDataSource extends Mock
    implements HouseholdRemoteDataSource {}

/// A bare `raise exception '<code>'` in Postgres carries SQLSTATE P0001 and
/// a message that is exactly the code string — this is what every named
/// error in spec §6.9.2's RPCs looks like once it reaches the client.
PostgrestException _named(String code) =>
    PostgrestException(message: code, code: 'P0001');

/// T-M2.2: `HouseholdRepository`'s RPC wrappers, exercised against a mocked
/// [HouseholdRemoteDataSource] (not a mocked `SupabaseClient` directly —
/// `rpc()` returns a `PostgrestFilterBuilder`, and this codebase's
/// established convention, per `update_check_repository_test.dart` and the
/// sync layer's `MockPullService`/`MockOutboxProcessor`, is to mock the thin
/// service boundary a repository actually depends on rather than the
/// Postgrest builder chain underneath it — see docs/DECISIONS.md).
///
/// Every method here is a pure network call — no Drift write, no outbox
/// entry — so these tests only assert the `Result` shape and the exact RPC
/// arguments, never touching the database. `createHousehold`/`joinHousehold`/
/// `leaveHousehold`/`deleteHousehold` do call `_triggerSync()` on success
/// (T-M2.7: the caller's household membership just changed server-side, and
/// the sync engine's own household-change check is what actually notices
/// and reconciles it) — tracked via [triggerSyncCalls] below and asserted on
/// those four groups' success cases. [ErrorMapper] doesn't yet recognise
/// these v2.0 error codes (that's T-M2.3's job), so every error case here
/// asserts `result.isErr` rather than a specific `Failure` subtype — pinning
/// that now would just have to be redone the moment T-M2.3 lands.
void main() {
  late MockHouseholdRemoteDataSource remote;
  late HouseholdRepository repo;
  late int triggerSyncCalls;

  setUp(() {
    remote = MockHouseholdRemoteDataSource();
    triggerSyncCalls = 0;
    // `updateName`'s Drift path is untouched by every test below — a real
    // in-memory database is still wired so nothing crashes if it ever were.
    repo = HouseholdRepository(
      remote,
      AppDatabase.forTesting(NativeDatabase.memory()),
      () => triggerSyncCalls++,
    );
  });

  group('createHousehold', () {
    test('success returns the household id, name, and invite code', () async {
      when(() => remote.createHousehold('My Family')).thenAnswer(
        (_) async => {
          'household_id': 'hh1',
          'name': 'My Family',
          'invite_code': 'ABCD1234',
        },
      );

      final result = await repo.createHousehold('My Family');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.householdId, 'hh1');
      expect(result.valueOrNull!.name, 'My Family');
      expect(result.valueOrNull!.inviteCode, 'ABCD1234');
      verify(() => remote.createHousehold('My Family')).called(1);
      expect(triggerSyncCalls, 1);
    });

    for (final code in [
      'not_authenticated',
      'name_required',
      'name_too_long',
      'already_in_household',
    ]) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.createHousehold(any())).thenThrow(_named(code));

        final result = await repo.createHousehold('My Family');

        expect(result.isErr, isTrue);
      });
    }
  });

  group('joinHousehold', () {
    test('success returns the household id and name', () async {
      when(
        () => remote.joinHousehold('ABCD1234'),
      ).thenAnswer((_) async => {'household_id': 'hh1', 'name': 'My Family'});

      final result = await repo.joinHousehold('ABCD1234');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.householdId, 'hh1');
      expect(result.valueOrNull!.name, 'My Family');
      verify(() => remote.joinHousehold('ABCD1234')).called(1);
      expect(triggerSyncCalls, 1);
    });

    for (final code in [
      'not_authenticated',
      'already_in_household',
      'invalid_invite',
      'household_inactive',
    ]) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.joinHousehold(any())).thenThrow(_named(code));

        final result = await repo.joinHousehold('ABCD1234');

        expect(result.isErr, isTrue);
      });
    }
  });

  group('leaveHousehold', () {
    test('success returns Ok', () async {
      when(() => remote.leaveHousehold()).thenAnswer((_) async {});

      final result = await repo.leaveHousehold();

      expect(result.isOk, isTrue);
      verify(() => remote.leaveHousehold()).called(1);
      expect(triggerSyncCalls, 1);
    });

    for (final code in ['not_in_household', 'last_admin']) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.leaveHousehold()).thenThrow(_named(code));

        final result = await repo.leaveHousehold();

        expect(result.isErr, isTrue);
      });
    }
  });

  group('setMemberRole', () {
    test('success passes the role name through and returns Ok', () async {
      when(() => remote.setMemberRole('u1', 'admin')).thenAnswer((_) async {});

      final result = await repo.setMemberRole('u1', MemberRole.admin);

      expect(result.isOk, isTrue);
      verify(() => remote.setMemberRole('u1', 'admin')).called(1);
    });

    for (final code in [
      'not_admin',
      'bad_role',
      'not_in_household',
      'not_a_member',
      'last_admin',
    ]) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.setMemberRole(any(), any())).thenThrow(_named(code));

        final result = await repo.setMemberRole('u1', MemberRole.member);

        expect(result.isErr, isTrue);
      });
    }
  });

  group('setMemberActive', () {
    test('success returns Ok', () async {
      when(() => remote.setMemberActive('u1', false)).thenAnswer((_) async {});

      final result = await repo.setMemberActive('u1', false);

      expect(result.isOk, isTrue);
      verify(() => remote.setMemberActive('u1', false)).called(1);
    });

    for (final code in [
      'not_admin',
      'not_a_member',
      'cannot_deactivate_self',
    ]) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.setMemberActive(any(), any()))
            .thenThrow(_named(code));

        final result = await repo.setMemberActive('u1', false);

        expect(result.isErr, isTrue);
      });
    }
  });

  group('removeMember', () {
    test('success returns Ok', () async {
      when(() => remote.removeMember('u1')).thenAnswer((_) async {});

      final result = await repo.removeMember('u1');

      expect(result.isOk, isTrue);
      verify(() => remote.removeMember('u1')).called(1);
    });

    for (final code in ['not_admin', 'use_leave_household', 'not_a_member']) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.removeMember(any())).thenThrow(_named(code));

        final result = await repo.removeMember('u1');

        expect(result.isErr, isTrue);
      });
    }
  });

  group('createInvite', () {
    Map<String, dynamic> inviteJson(String code) => {
      'id': 'inv1',
      'code': code,
      'expires_at': '2026-10-01T00:00:00Z',
      'max_uses': 20,
      'use_count': 0,
    };

    test('success creates then re-fetches the active invite, defaulting '
        'days/maxUses', () async {
      when(() => remote.createInvite(days: 30, maxUses: 20))
          .thenAnswer((_) async => 'WXYZ5678');
      when(() => remote.fetchActiveInvite('hh1'))
          .thenAnswer((_) async => inviteJson('WXYZ5678'));

      final result = await repo.createInvite(householdId: 'hh1');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.code, 'WXYZ5678');
      expect(result.valueOrNull!.maxUses, 20);
      verify(() => remote.createInvite(days: 30, maxUses: 20)).called(1);
      verify(() => remote.fetchActiveInvite('hh1')).called(1);
    });

    test('a custom expiry/use-cap is passed straight through', () async {
      when(() => remote.createInvite(days: 7, maxUses: 5))
          .thenAnswer((_) async => 'WXYZ5678');
      when(() => remote.fetchActiveInvite('hh1'))
          .thenAnswer((_) async => inviteJson('WXYZ5678'));

      await repo.createInvite(householdId: 'hh1', days: 7, maxUses: 5);

      verify(() => remote.createInvite(days: 7, maxUses: 5)).called(1);
    });

    for (final code in ['not_admin', 'not_in_household', 'bad_expiry']) {
      test('$code surfaces as an error Result', () async {
        when(
          () => remote.createInvite(
            days: any(named: 'days'),
            maxUses: any(named: 'maxUses'),
          ),
        ).thenThrow(_named(code));

        final result = await repo.createInvite(householdId: 'hh1');

        expect(result.isErr, isTrue);
      });
    }
  });

  group('fetchActiveInvite', () {
    test('returns the active invite when one exists', () async {
      when(() => remote.fetchActiveInvite('hh1')).thenAnswer(
        (_) async => {
          'id': 'inv1',
          'code': 'ABCD1234',
          'expires_at': '2026-10-01T00:00:00Z',
          'max_uses': 20,
          'use_count': 2,
        },
      );

      final result = await repo.fetchActiveInvite('hh1');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull!.code, 'ABCD1234');
      expect(result.valueOrNull!.useCount, 2);
    });

    test('returns null when no invite is active', () async {
      when(() => remote.fetchActiveInvite('hh1')).thenAnswer((_) async => null);

      final result = await repo.fetchActiveInvite('hh1');

      expect(result.isOk, isTrue);
      expect(result.valueOrNull, isNull);
    });

    test('an unexpected failure surfaces as an error Result', () async {
      when(() => remote.fetchActiveInvite('hh1')).thenThrow(Exception('boom'));

      final result = await repo.fetchActiveInvite('hh1');

      expect(result.isErr, isTrue);
    });
  });

  group('revokeInvites', () {
    test('success returns Ok', () async {
      when(() => remote.revokeInvites()).thenAnswer((_) async {});

      final result = await repo.revokeInvites();

      expect(result.isOk, isTrue);
      verify(() => remote.revokeInvites()).called(1);
    });

    test('not_admin surfaces as an error Result', () async {
      when(() => remote.revokeInvites()).thenThrow(_named('not_admin'));

      final result = await repo.revokeInvites();

      expect(result.isErr, isTrue);
    });
  });

  group('touchActivity', () {
    test('success returns Ok', () async {
      when(() => remote.touchActivity()).thenAnswer((_) async {});

      final result = await repo.touchActivity();

      expect(result.isOk, isTrue);
      verify(() => remote.touchActivity()).called(1);
    });

    test('an unexpected failure still surfaces as an error Result', () async {
      when(() => remote.touchActivity()).thenThrow(Exception('boom'));

      final result = await repo.touchActivity();

      expect(result.isErr, isTrue);
    });
  });

  group('deleteHousehold', () {
    test('success returns Ok', () async {
      when(() => remote.deleteHousehold()).thenAnswer((_) async {});

      final result = await repo.deleteHousehold();

      expect(result.isOk, isTrue);
      verify(() => remote.deleteHousehold()).called(1);
      expect(triggerSyncCalls, 1);
    });

    for (final code in [
      'not_admin',
      'not_in_household',
      'household_not_empty',
    ]) {
      test('$code surfaces as an error Result', () async {
        when(() => remote.deleteHousehold()).thenThrow(_named(code));

        final result = await repo.deleteHousehold();

        expect(result.isErr, isTrue);
      });
    }
  });
}
