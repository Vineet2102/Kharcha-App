import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/profile_repository.dart';
import '../../../routing/routes.dart';
import '../../auth/controllers/sign_out_controller.dart';

/// Settings hub (spec §11.13). Full UI (household, notifications, data,
/// about, diagnostics) is built out in Phase 14 — this carries the
/// sign-out action needed to exercise T-3.6, plus early links to the
/// Phase 5 management screens (Categories/Payment methods), since without
/// them those screens are otherwise unreachable from the UI.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('This clears everything stored on this phone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(signOutControllerProvider.notifier).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(currentProfileProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const CircleAvatar(child: Icon(Icons.person_outline)),
            title: Text(profile?.displayName ?? 'Profile'),
            subtitle: Text(profile?.isAdmin == true ? 'Admin' : 'Member'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            onTap: () => context.push(AppRoutes.categories),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Payment methods'),
            onTap: () => context.push(AppRoutes.paymentMethods),
          ),
          ListTile(
            leading: const Icon(Icons.attach_money_outlined),
            title: const Text('Income'),
            onTap: () => context.push(AppRoutes.income),
          ),
          ListTile(
            leading: const Icon(Icons.pie_chart_outline),
            title: const Text('Budgets'),
            onTap: () => context.push(AppRoutes.budgets),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () => _confirmSignOut(context, ref),
          ),
        ],
      ),
    );
  }
}
