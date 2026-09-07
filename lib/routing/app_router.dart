import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart'
    show ProviderSubscription;
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
import '../features/household/screens/household_management_screen.dart';
import '../features/income/screens/income_detail_screen.dart';
import '../features/income/screens/income_list_screen.dart';
import '../features/onboarding/screens/create_household_screen.dart';
import '../features/onboarding/screens/join_household_screen.dart';
import '../features/onboarding/screens/onboarding_gate_screen.dart';
import '../features/payment_methods/screens/payment_method_list_screen.dart';
import '../features/receipts/screens/receipt_viewer_screen.dart';
import '../features/recurring/screens/recurring_detail_screen.dart';
import '../features/recurring/screens/recurring_list_screen.dart';
import '../features/notifications/screens/notification_settings_screen.dart';
import '../features/settings/screens/diagnostics_screen.dart';
import '../features/settings/screens/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../data/remote/supabase_client_provider.dart';
import '../data/repositories/profile_repository.dart';
import '../domain/models/expense.dart' as domain;
import 'go_router_refresh_stream.dart';
import 'root_navigator_key.dart';
import 'routes.dart';

part 'app_router.g.dart';

/// Notifies go_router's `redirect` whenever the signed-in member's household
/// id changes (spec T-M2.8) — without this, `redirect` would only re-run on
/// a navigation attempt or a Supabase auth event, and neither fires when a
/// household is created/joined/left except through this app's own screens
/// explicitly navigating afterward (which works fine on its own), or when
/// something *external* changes it (an admin removing this member on another
/// device, discovered by `SyncEngine`'s own `refreshOwnProfile`, T-M2.7) —
/// that case has no navigation attempt of its own to trigger a re-check.
class _HouseholdChangeNotifier extends ChangeNotifier {
  _HouseholdChangeNotifier(Ref ref) {
    _sub = ref.listen<String?>(currentHouseholdIdProvider, (previous, next) {
      if (previous != next) notifyListeners();
    });
  }

  late final ProviderSubscription<String?> _sub;

  @override
  void dispose() {
    _sub.close();
    super.dispose();
  }
}

/// The route map from spec §10.1, plus the auth redirect: a three-state gate
/// (spec T-M2.8) resolved in order — no session, session with email
/// unconfirmed, confirmed with no household, confirmed in a household — each
/// state's own allowed set per the spec's table. `/splash` isn't one of any
/// state's allowed destinations, so it always falls through to whichever one
/// applies and is redirected onward immediately — the same job `redirect`
/// already did for it pre-T-M2.8 (`SplashScreen` itself has no navigation
/// logic of its own; its `CircularProgressIndicator` animates forever if
/// nothing ever redirects away from it, which is exactly what an earlier
/// version of this gate got wrong by special-casing splash to stay put). The
/// household state reads `currentHouseholdIdProvider`, which resolves from
/// the **locally cached** profile (T-M2.1), so this gate resolves correctly
/// offline — a member in aeroplane mode is never bounced to onboarding
/// because a network call failed. Not implemented: spec's narrower "no
/// cached profile at all and offline → hold on `/splash` with a retry"
/// carve-out — that account state (very first launch, no local data, no
/// network) falls through to the no-household branch instead, landing on
/// `/onboarding` rather than holding; revisit if this proves confusing in
/// practice.
///
/// `/onboarding/create` and `/onboarding/join` are deliberately exempt from
/// the "already in a household → bounce to the dashboard" rule below: right
/// after creating/joining, the household id flips to non-null while the
/// screen is still showing its own success view (the invite code reveal, or
/// "You've joined \<name\>") — forcing a redirect at that exact moment would
/// yank it away before the user ever sees it. Those two screens navigate
/// onward themselves once the user is ready (spec F-15's own "Then a full
/// sync and into the dashboard"). Only the bare `/onboarding` gate itself
/// redirects once a household exists, since showing the two big create/join
/// choices no longer makes sense at that point.
@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  final client = ref.watch(supabaseClientProvider);
  final authRefresh = GoRouterRefreshStream(client.auth.onAuthStateChange);
  ref.onDispose(authRefresh.dispose);
  final householdRefresh = _HouseholdChangeNotifier(ref);
  ref.onDispose(householdRefresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: Listenable.merge([authRefresh, householdRefresh]),
    redirect: (context, state) {
      final loc = state.matchedLocation;

      final session = client.auth.currentSession;
      final signedOutReachable =
          loc == AppRoutes.login ||
          loc == AppRoutes.signup ||
          loc == AppRoutes.verifyEmail;
      if (session == null) {
        return signedOutReachable ? null : AppRoutes.login;
      }

      final emailConfirmed = client.auth.currentUser?.emailConfirmedAt != null;
      if (!emailConfirmed) {
        return loc == AppRoutes.verifyEmail ? null : AppRoutes.verifyEmail;
      }

      final householdId = ref.read(currentHouseholdIdProvider);
      final onOnboardingFlow = loc.startsWith(AppRoutes.onboarding);
      if (householdId == null) {
        if (signedOutReachable) return AppRoutes.onboarding;
        return onOnboardingFlow ? null : AppRoutes.onboarding;
      }

      final blockedNowInHousehold =
          signedOutReachable || loc == AppRoutes.onboarding;
      return blockedNowInHousehold ? AppRoutes.dashboard : null;
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
      GoRoute(
        path: AppRoutes.onboarding,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const OnboardingGateScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingCreate,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const CreateHouseholdScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboardingJoin,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const JoinHouseholdScreen(),
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
        path: AppRoutes.household,
        parentNavigatorKey: rootNavigatorKey,
        builder: (context, state) => const HouseholdManagementScreen(),
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
