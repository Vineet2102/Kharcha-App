import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/analytics/screens/analytics_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/signup_screen.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/verify_email_screen.dart';
import '../features/budgets/screens/budget_detail_screen.dart';
import '../features/budgets/screens/budget_list_screen.dart';
import '../features/categories/screens/category_list_screen.dart';
import '../features/dashboard/screens/dashboard_screen.dart';
import '../features/expenses/screens/expense_detail_screen.dart';
import '../features/expenses/screens/expense_list_screen.dart';
import '../features/export/screens/export_screen.dart';
import '../features/income/screens/income_detail_screen.dart';
import '../features/income/screens/income_list_screen.dart';
import '../features/payment_methods/screens/payment_method_list_screen.dart';
import '../features/receipts/screens/receipt_viewer_screen.dart';
import '../features/recurring/screens/recurring_detail_screen.dart';
import '../features/recurring/screens/recurring_list_screen.dart';
import '../features/notifications/screens/notification_settings_screen.dart';
import '../features/settings/screens/diagnostics_screen.dart';
import '../features/settings/screens/members_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../data/remote/supabase_client_provider.dart';
import '../domain/models/expense.dart' as domain;
import 'go_router_refresh_stream.dart';
import 'root_navigator_key.dart';
import 'routes.dart';

part 'app_router.g.dart';

/// The route map from spec §10.1, plus the auth redirect (T-3.4): a
/// signed-out member always lands on `/login`; a signed-in member is bounced
/// off `/login`/`/splash` straight to the dashboard. `redirect` re-runs
/// whenever `refreshListenable` fires, i.e. on every Supabase auth event.
///
/// `/signup` and `/verify-email` (spec F-15, T-M2.4) join `/login` as the
/// signed-out-reachable set — a fresh account has no session at all until
/// its email is confirmed (T-M1.8), so without this a signed-out redirect
/// would bounce a brand-new user straight back to `/login` mid-flow. This
/// is still v1.0's plain signed-in/signed-out binary, not the three-state
/// (no session / confirmed-but-no-household / normal) gate spec'd for
/// T-M2.8 — that task replaces this `redirect` wholesale once the
/// onboarding screens it depends on exist.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  final refreshStream = GoRouterRefreshStream(client.auth.onAuthStateChange);
  ref.onDispose(refreshStream.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: refreshStream,
    redirect: (context, state) {
      final signedIn = client.auth.currentSession != null;
      final loc = state.matchedLocation;
      final publicUnauthed =
          loc == AppRoutes.login ||
          loc == AppRoutes.signup ||
          loc == AppRoutes.verifyEmail;
      final atSplash = loc == AppRoutes.splash;

      if (!signedIn) return publicUnauthed ? null : AppRoutes.login;
      if (publicUnauthed || atSplash) return AppRoutes.dashboard;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.signup,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            VerifyEmailScreen(email: state.extra as String?),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                builder: (context, state) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.expenses,
                builder: (context, state) => const ExpenseListScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.analytics,
                builder: (context, state) => const AnalyticsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                builder: (context, state) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.expenseNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            ExpenseDetailScreen(duplicateFrom: state.extra as domain.Expense?),
      ),
      GoRoute(
        path: AppRoutes.expenseDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            ExpenseDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.income,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const IncomeListScreen(),
      ),
      GoRoute(
        path: AppRoutes.incomeNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const IncomeDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.incomeDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            IncomeDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.budgets,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const BudgetListScreen(),
      ),
      GoRoute(
        path: AppRoutes.budgetNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            BudgetDetailScreen(initialMonth: state.extra as DateTime?),
      ),
      GoRoute(
        path: AppRoutes.budgetDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            BudgetDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.recurring,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RecurringListScreen(),
      ),
      GoRoute(
        path: AppRoutes.recurringNew,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const RecurringDetailScreen(),
      ),
      GoRoute(
        path: AppRoutes.recurringDetail,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) =>
            RecurringDetailScreen(id: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.categories,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CategoryListScreen(),
      ),
      GoRoute(
        path: AppRoutes.paymentMethods,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const PaymentMethodListScreen(),
      ),
      GoRoute(
        path: AppRoutes.members,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const MembersScreen(),
      ),
      GoRoute(
        path: AppRoutes.export,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const ExportScreen(),
      ),
      GoRoute(
        path: AppRoutes.receiptViewer,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => ReceiptViewerScreen(
          attachmentId: state.pathParameters['attachmentId']!,
        ),
      ),
      GoRoute(
        path: AppRoutes.diagnostics,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const DiagnosticsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notificationSettings,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const NotificationSettingsScreen(),
      ),
    ],
  );
}
