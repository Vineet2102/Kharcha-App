/// Route path constants (spec §10.1). Kept separate from `app_router.dart`
/// so screens can reference a path without importing GoRouter's config.
class AppRoutes {
  const AppRoutes._();

  static const splash = '/splash';
  static const login = '/login';
  static const signup = '/signup';
  static const verifyEmail = '/verify-email';
  static const onboarding = '/onboarding';
  static const onboardingCreate = '/onboarding/create';
  static const onboardingJoin = '/onboarding/join';

  static const dashboard = '/';
  static const expenses = '/expenses';
  static const analytics = '/analytics';
  static const settings = '/settings';

  static const expenseNew = '/expense/new';
  static const expenseDetail = '/expense/:id';
  static const income = '/income';
  static const incomeNew = '/income/new';
  static const incomeDetail = '/income/:id';

  static const budgets = '/budgets';
  static const budgetNew = '/budgets/new';
  static const budgetDetail = '/budgets/:id';

  static const recurring = '/recurring';
  static const recurringNew = '/recurring/new';
  static const recurringDetail = '/recurring/:id';

  static const categories = '/categories';
  static const paymentMethods = '/payment-methods';
  static const household = '/household';
  static const export = '/export';
  static const receiptViewer = '/receipt/:attachmentId';
  static const diagnostics = '/diagnostics';
  static const notificationSettings = '/notifications';

  static String expenseDetailPath(String id) => '/expense/$id';
  static String incomeDetailPath(String id) => '/income/$id';
  static String budgetDetailPath(String id) => '/budgets/$id';
  static String recurringDetailPath(String id) => '/recurring/$id';
  static String receiptViewerPath(String attachmentId) =>
      '/receipt/$attachmentId';
}
