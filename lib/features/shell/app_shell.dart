import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'widgets/sync_banner.dart';

/// Bottom-nav shell for the 4 main tabs (spec §10.2). A centre FAB on
/// Dashboard/Expenses opens Add Expense; long-press opens Add Income.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  static const _labels = ['Dashboard', 'Expenses', 'Analytics', 'Settings'];
  static const _icons = [
    Icons.dashboard_outlined,
    Icons.receipt_long_outlined,
    Icons.bar_chart_outlined,
    Icons.settings_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final showFab = navigationShell.currentIndex <= 1;
    return Scaffold(
      body: Column(
        children: [
          const SyncBanner(),
          Expanded(child: navigationShell),
        ],
      ),
      floatingActionButton: showFab
          ? GestureDetector(
              onLongPress: () => context.push('/income/new'),
              child: FloatingActionButton(
                onPressed: () => context.push('/expense/new'),
                tooltip: 'Add expense (long-press for income)',
                child: const Icon(Icons.add),
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (index) => navigationShell.goBranch(
          index,
          initialLocation: index == navigationShell.currentIndex,
        ),
        destinations: [
          for (var i = 0; i < _labels.length; i++)
            NavigationDestination(icon: Icon(_icons[i]), label: _labels[i]),
        ],
      ),
    );
  }
}
