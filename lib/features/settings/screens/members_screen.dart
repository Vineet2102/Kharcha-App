import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/category_visuals.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../domain/models/enums.dart';

/// Member list; admin sees roles and can toggle `is_active` (spec §1.5,
/// T-14.3). A member sees the same list read-only — RLS's `pr_update_self`
/// (`id = auth.uid() or is_admin()`) blocks the write server-side
/// regardless, this just hides the control client-side, same precedent as
/// every other admin-only control in this app.
class MembersScreen extends ConsumerWidget {
  const MembersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentProfileProvider).value;
    final members = ref.watch(householdProfilesProvider).value ?? const [];
    final isAdmin = me?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Members')),
      body: members.isEmpty
          ? const Center(child: Text('No members yet.'))
          : ListView.separated(
              itemCount: members.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final member = members[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colourFromHex(member.colourHex),
                    foregroundColor: Colors.white,
                    child: Text(
                      member.displayName.isEmpty
                          ? '?'
                          : member.displayName[0].toUpperCase(),
                    ),
                  ),
                  title: Text(member.displayName),
                  subtitle: Text(
                    member.role == MemberRole.admin ? 'Admin' : 'Member',
                  ),
                  trailing: isAdmin
                      ? Switch(
                          value: member.isActive,
                          onChanged: (value) => ref
                              .read(profileRepositoryProvider)
                              .setActive(member.id, value),
                        )
                      : Text(
                          member.isActive ? 'Active' : 'Inactive',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                );
              },
            ),
    );
  }
}
