import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../core/time/app_time.dart';
import '../../../data/repositories/export_repository.dart';
import '../../../data/repositories/household_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/enums.dart';
import '../../../domain/models/household.dart' as domain;
import '../../../domain/models/household_invite.dart';
import '../../../domain/models/profile.dart' as domain;
import '../../../routing/routes.dart';

String _dateLabel(DateTime instant) {
  final ist = AppTime.toIst(instant);
  return '${ist.day}/${ist.month}/${ist.year}';
}

/// Household & member management (spec F-16, T-M2.9), reachable from
/// Settings → Household. Every admin-only control below is *absent*, not
/// disabled, for a member — RLS is the real enforcement server-side.
class HouseholdManagementScreen extends ConsumerWidget {
  const HouseholdManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider).value;
    final me = ref.watch(currentProfileProvider).value;
    final members = ref.watch(householdProfilesProvider).value ?? const [];
    final isAdmin = me?.isAdmin ?? false;

    if (household == null || me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Household')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final soleRemainingMember = isAdmin && members.length == 1;

    return Scaffold(
      appBar: AppBar(title: const Text('Household')),
      body: ListView(
        children: [
          _Header(
            household: household,
            memberCount: members.length,
            isAdmin: isAdmin,
          ),
          if (isAdmin) ...[
            const Divider(height: 1),
            _InviteSection(householdId: household.id),
          ],
          const Divider(height: 1),
          _MembersSection(members: members, me: me, isAdmin: isAdmin),
          const Divider(height: 1),
          _LeaveTile(household: household),
          if (soleRemainingMember) _DeleteTile(household: household),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.household,
    required this.memberCount,
    required this.isAdmin,
  });

  final domain.Household household;
  final int memberCount;
  final bool isAdmin;

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: household.name);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Household name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !context.mounted) return;
    await ref.read(householdRepositoryProvider).updateName(household.id, name);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      household.name,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (isAdmin)
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Rename',
                      onPressed: () => _rename(context, ref),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$memberCount member${memberCount == 1 ? '' : 's'} · '
                'Created ${_dateLabel(household.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InviteSection extends ConsumerWidget {
  const _InviteSection({required this.householdId});

  final String householdId;

  Future<void> _copy(BuildContext context, String formatted) async {
    await Clipboard.setData(ClipboardData(text: formatted));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Code copied')));
    }
  }

  void _share(String formatted) => SharePlus.instance.share(
    ShareParams(
      text:
          'Join my household on Kharcha. Install the app, then enter code '
          '$formatted.',
    ),
  );

  Future<void> _regenerate(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<({int days, int maxUses})>(
      context: context,
      builder: (context) => const _RegenerateDialog(),
    );
    if (choice == null || !context.mounted) return;
    final result = await ref
        .read(householdRepositoryProvider)
        .createInvite(
          householdId: householdId,
          days: choice.days,
          maxUses: choice.maxUses,
        );
    if (!context.mounted) return;
    ref.invalidate(activeInviteProvider(householdId));
    final failure = result.failureOrNull;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _revoke(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke invite code?'),
        content: const Text(
          "No one will be able to join with the current code any more.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref.read(householdRepositoryProvider).revokeInvites();
    if (!context.mounted) return;
    ref.invalidate(activeInviteProvider(householdId));
    final failure = result.failureOrNull;
    if (failure != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inviteAsync = ref.watch(activeInviteProvider(householdId));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: inviteAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Row(
          children: [
            const Expanded(child: Text("Couldn't load the invite code.")),
            TextButton(
              onPressed: () =>
                  ref.invalidate(activeInviteProvider(householdId)),
              child: const Text('Retry'),
            ),
          ],
        ),
        data: (invite) => invite == null
            ? Row(
                children: [
                  const Expanded(child: Text('No active invite code')),
                  FilledButton(
                    onPressed: () => _regenerate(context, ref),
                    child: const Text('Create'),
                  ),
                ],
              )
            : _InviteCard(
                invite: invite,
                onCopy: (code) => _copy(context, code),
                onShare: _share,
                onRegenerate: () => _regenerate(context, ref),
                onRevoke: () => _revoke(context, ref),
              ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  const _InviteCard({
    required this.invite,
    required this.onCopy,
    required this.onShare,
    required this.onRegenerate,
    required this.onRevoke,
  });

  final HouseholdInvite invite;
  final void Function(String formatted) onCopy;
  final void Function(String formatted) onShare;
  final VoidCallback onRegenerate;
  final VoidCallback onRevoke;

  String get _formatted {
    final code = invite.code;
    return code.length == 8
        ? '${code.substring(0, 4)}-${code.substring(4)}'
        : code;
  }

  @override
  Widget build(BuildContext context) {
    final daysLeft = invite.expiresAt.difference(DateTime.now().toUtc()).inDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _formatted,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(letterSpacing: 2),
        ),
        const SizedBox(height: 4),
        Text(
          '${daysLeft > 0 ? 'Expires in $daysLeft day${daysLeft == 1 ? '' : 's'}' : 'Expired'} '
          '· used ${invite.useCount} of ${invite.maxUses}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: () => onCopy(_formatted),
              icon: const Icon(Icons.copy_outlined),
              label: const Text('Copy'),
            ),
            OutlinedButton.icon(
              onPressed: () => onShare(_formatted),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Share'),
            ),
            TextButton(
              onPressed: onRegenerate,
              child: const Text('Regenerate'),
            ),
            TextButton(onPressed: onRevoke, child: const Text('Revoke')),
          ],
        ),
      ],
    );
  }
}

class _RegenerateDialog extends StatefulWidget {
  const _RegenerateDialog();

  @override
  State<_RegenerateDialog> createState() => _RegenerateDialogState();
}

class _RegenerateDialogState extends State<_RegenerateDialog> {
  int _days = 30;
  int _maxUses = 20;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Regenerate invite code?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Anyone who has the old code won't be able to use it."),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _days,
            decoration: const InputDecoration(labelText: 'Expires after'),
            items: const [1, 7, 30, 90, 365]
                .map((d) => DropdownMenuItem(value: d, child: Text('$d days')))
                .toList(),
            onChanged: (value) => setState(() => _days = value ?? _days),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            initialValue: _maxUses,
            decoration: const InputDecoration(labelText: 'Max uses'),
            items: const [1, 5, 20, 100]
                .map((u) => DropdownMenuItem(value: u, child: Text('$u uses')))
                .toList(),
            onChanged: (value) => setState(() => _maxUses = value ?? _maxUses),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(context, (days: _days, maxUses: _maxUses)),
          child: const Text('Regenerate'),
        ),
      ],
    );
  }
}

class _MembersSection extends ConsumerWidget {
  const _MembersSection({
    required this.members,
    required this.me,
    required this.isAdmin,
  });

  final List<domain.Profile> members;
  final domain.Profile me;
  final bool isAdmin;

  Future<void> _setRole(
    BuildContext context,
    WidgetRef ref,
    domain.Profile member,
    MemberRole role,
  ) async {
    final result = await ref
        .read(householdRepositoryProvider)
        .setMemberRole(member.id, role);
    final failure = result.failureOrNull;
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _setActive(
    BuildContext context,
    WidgetRef ref,
    domain.Profile member,
    bool active,
  ) async {
    final result = await ref
        .read(householdRepositoryProvider)
        .setMemberActive(member.id, active);
    final failure = result.failureOrNull;
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    domain.Profile member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${member.displayName}?'),
        content: Text(
          'Their past expenses stay in this household. '
          "They'll need a new code to rejoin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref
        .read(householdRepositoryProvider)
        .removeMember(member.id);
    final failure = result.failureOrNull;
    if (failure != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final member in members)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colourFromHex(member.colourHex),
              foregroundColor: Colors.white,
              child: Text(
                member.displayName.isEmpty
                    ? '?'
                    : member.displayName[0].toUpperCase(),
              ),
            ),
            title: Text(
              member.id == me.id
                  ? '${member.displayName} (you)'
                  : member.displayName,
            ),
            subtitle: Text(
              '${member.isAdmin ? 'Admin' : 'Member'}'
              '${member.joinedAt != null ? ' · joined ${_dateLabel(member.joinedAt!)}' : ''}'
              '${member.isActive ? '' : ' · Inactive'}',
            ),
            trailing: (isAdmin && member.id != me.id)
                ? PopupMenuButton<String>(
                    onSelected: (action) {
                      switch (action) {
                        case 'make_admin':
                          _setRole(context, ref, member, MemberRole.admin);
                        case 'make_member':
                          _setRole(context, ref, member, MemberRole.member);
                        case 'deactivate':
                          _setActive(context, ref, member, false);
                        case 'reactivate':
                          _setActive(context, ref, member, true);
                        case 'remove':
                          _remove(context, ref, member);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: member.isAdmin ? 'make_member' : 'make_admin',
                        child: Text(
                          member.isAdmin ? 'Make member' : 'Make admin',
                        ),
                      ),
                      PopupMenuItem(
                        value: member.isActive ? 'deactivate' : 'reactivate',
                        child: Text(
                          member.isActive ? 'Deactivate' : 'Reactivate',
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove from household'),
                      ),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}

class _LeaveTile extends ConsumerWidget {
  const _LeaveTile({required this.household});

  final domain.Household household;

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave ${household.name}?'),
        content: Text(
          'Your expenses stay with this household — you won\'t be able to '
          'see them any more. Your account stays, and you can create or '
          'join another household.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final result = await ref.read(householdRepositoryProvider).leaveHousehold();
    if (!context.mounted) return;
    result.fold(
      (_) => context.go(AppRoutes.onboarding),
      (failure) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: const Icon(Icons.logout),
      title: const Text('Leave household'),
      onTap: () => _leave(context, ref),
    );
  }
}

class _DeleteTile extends ConsumerWidget {
  const _DeleteTile({required this.household});

  final domain.Household household;

  Future<void> _exportBackup(BuildContext context, WidgetRef ref) async {
    final result = await ref
        .read(exportRepositoryProvider)
        .exportFullBackupJson(householdId: household.id);
    if (!context.mounted) return;
    result.fold(
      (file) =>
          SharePlus.instance.share(ShareParams(files: [XFile(file.path)])),
      (failure) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete household?'),
        content: Text(
          'This permanently deletes every expense, budget, and receipt in '
          '${household.name}. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => _exportBackup(context, ref),
            child: const Text('Export a full backup first'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (proceed != true || !context.mounted) return;

    final typedName = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Confirm deletion'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Type "${household.name}" to confirm',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (typedName != household.name || !context.mounted) return;

    final result = await ref
        .read(householdRepositoryProvider)
        .deleteHousehold();
    if (!context.mounted) return;
    result.fold(
      (_) => context.go(AppRoutes.onboarding),
      (failure) =>
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(failure.message))),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Icon(
        Icons.delete_forever_outlined,
        color: Theme.of(context).colorScheme.error,
      ),
      title: Text(
        'Delete household',
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      onTap: () => _delete(context, ref),
    );
  }
}
