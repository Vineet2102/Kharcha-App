import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/analytics/screens/analytics_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/budgets/screens/budget_detail_screen.dart';
import '../features/budgets/screens/budget_list_screen.dart';
import '../features/categories/screens/category_list_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/expenses/screens/expense_detail_screen.dart';
import '../features/expenses/screens/expense_list_screen.dart';
import '../features/export/screens/export_screen.dart';
import '../features/income/screens/income_detail_screen.dart';
import '../features/payment_methods/screens/payment_method_list_screen.dart';
import '../features/receipts/screens/receipt_viewer_screen.dart';
import '../features/recurring/screens/recurring_detail_screen.dart';
import '../features/recurring/screens/recurring_list_screen.dart';
import '../features/settings/screens/diagnostics_screen.dart';
import '../features/settings/screens/members_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../data/remote/supabase_client_provider.dart';
import 'go_router_refresh_stream.dart';
import 'routes.dart';

part 'app_router.g.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

/// The route map from spec §10.1, plus the auth redirect (T-3.4): a
/// signed-out member always lands on `/login`; a signed-in member is bounced
/// off `/login`/`/splash` straight to the dashboard. `redirect` re-runs
/// whenever `refreshListenable` fires, i.e. on every Supabase auth event.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  final refreshStream = GoRouterRefreshStream(client.auth.onAuthStateChange);
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final signedIn = client.auth.currentSession != null;
      final loggingIn = state.matchedLocation == AppRoutes.login;
      final atSplash = state.matchedLocation == AppRoutes.splash;

      if (!signedIn) return loggingIn ? null : AppRoutes.login;
      if (loggingIn || atSplash) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.login, builder: (context, state) => const LoginScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) => AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.dashboard, builder: (context, state) => const DashboardScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.expenses, builder: (context, state) => const ExpenseListScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.analytics, builder: (context, state) => const AnalyticsScreen())],
          ),
          StatefulShellBranch(
            routes: [GoRoute(path: AppRoutes.settings, builder: (context, state) => const SettingsScreen())],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.expenseNew,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ExpenseDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.expenseDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ExpenseDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.incomeNew,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const IncomeDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.incomeDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => IncomeDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.budgets,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BudgetListScreen(),
      ),
      GoRoute(
        path: AppRoutes.budgetNew,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BudgetDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.budgetDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => BudgetDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.recurring,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RecurringListScreen(),
      ),
      GoRoute(
        path: AppRoutes.recurringNew,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RecurringDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.recurringDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => RecurringDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.categories,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CategoryListScreen(),
      ),
      GoRoute(
        path: AppRoutes.paymentMethods,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PaymentMethodListScreen(),
      ),
      GoRoute(
        path: AppRoutes.members,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const MembersScreen(),
      ),
      GoRoute(
        path: AppRoutes.export,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ExportScreen(),
      ),
      GoRoute(
        path: AppRoutes.receiptViewer,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ReceiptViewerScreen(attachmentId: state.pathParameters['attachmentId']!),
      ),
      GoRoute(
        path: AppRoutes.diagnostics,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DiagnosticsScreen(),
      ),
    ],
  );
}
