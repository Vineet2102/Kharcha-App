import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/config/app_config.dart';
import '../../../core/db/database_provider.dart';
import '../../../data/repositories/household_repository.dart';
import '../../../data/repositories/profile_repository.dart';
import '../../../data/repositories/update_check_repository.dart';
import '../../../data/sync/sync_engine.dart';
import '../../../routing/routes.dart';
import '../../auth/controllers/sign_out_controller.dart';
import 'change_password_dialog.dart';
import 'edit_profile_sheet.dart';

/// Settings hub (spec §11.13): Profile, Household, Manage, Notifications,
/// Data, About, Diagnostics.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;

  Future<void> _confirmSignOut() async {
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

  Future<void> _syncNow() async {
    setState(() => _busy = true);
    await ref.read(syncEngineProvider).sync();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Sync complete.')));
  }

  Future<void> _clearCacheAndResync() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear local cache?'),
        content: const Text(
          'Deletes everything stored on this phone and re-downloads it from '
          'the server. You stay signed in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear & re-download'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    await ref.read(appDatabaseProvider).wipeAll();
    await ref.read(syncEngineProvider).sync();
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cache cleared and re-synced.')),
    );
  }

  Future<void> _checkForUpdates() async {
    setState(() => _busy = true);
    await ref.read(updateCheckControllerProvider.notifier).check(force: true);
    if (!mounted) return;
    setState(() => _busy = false);
    final result = ref.read(updateCheckControllerProvider);
    final message = switch (result) {
      UpdateAvailable(:final release) =>
        'Version ${release.versionName} is available.',
      Blocked() => 'An update is required to keep syncing.',
      _ => "You're up to date.",
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(currentProfileProvider).value;
    final household = ref.watch(householdProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? 0.6 : 1,
          child: ListView(
            children: [
              _SectionHeader('Profile'),
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                title: Text(profile?.displayName ?? 'Profile'),
                subtitle: Text(profile?.isAdmin == true ? 'Admin' : 'Member'),
                onTap: profile == null
                    ? null
                    : () => showEditProfileSheet(context, profile),
              ),
              ListTile(
                leading: const Icon(Icons.lock_outline),
                title: const Text('Change password'),
                onTap: () => showChangePasswordDialog(context),
              ),
              ListTile(
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: _confirmSignOut,
              ),
              const Divider(),
              _SectionHeader('Household'),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: Text(household?.name ?? '—'),
                subtitle: const Text('Household'),
                onTap: () => context.push(AppRoutes.household),
              ),
              const ListTile(
                leading: Icon(Icons.currency_rupee),
                title: Text('Currency'),
                subtitle: Text('INR (₹)'),
              ),
              const Divider(),
              _SectionHeader('Manage'),
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
              ListTile(
                leading: const Icon(Icons.repeat),
                title: const Text('Recurring'),
                onTap: () => context.push(AppRoutes.recurring),
              ),
              const Divider(),
              _SectionHeader('Notifications'),
              ListTile(
                leading: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                onTap: () => context.push(AppRoutes.notificationSettings),
              ),
              const Divider(),
              _SectionHeader('Data'),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Export'),
                onTap: () => context.push(AppRoutes.export),
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Sync now'),
                onTap: _syncNow,
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Clear local cache and re-download'),
                onTap: _clearCacheAndResync,
              ),
              const Divider(),
              _SectionHeader('About'),
              const _AboutTile(),
              ListTile(
                leading: const Icon(Icons.system_update_outlined),
                title: const Text('Check for updates'),
                onTap: _checkForUpdates,
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: const Text('Diagnostics'),
                onTap: () => context.push(AppRoutes.diagnostics),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      title,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// App version/build + backend host (spec §11.13 "About" — a literal
/// Supabase *region* isn't available from `AppConfig`, so the project's
/// host stands in for it; see docs/DECISIONS.md).
class _AboutTile extends StatelessWidget {
  const _AboutTile();

  @override
  Widget build(BuildContext context) {
    final host = Uri.tryParse(AppConfig.supabaseUrl)?.host ?? 'unknown';
    return FutureBuilder<PackageInfo>(
      future: PackageInfo.fromPlatform(),
      builder: (context, snapshot) {
        final info = snapshot.data;
        final version = info == null
            ? '…'
            : '${info.version} (${info.buildNumber})';
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('Kharcha $version'),
          subtitle: Text('Backend: $host'),
        );
      },
    );
  }
}
