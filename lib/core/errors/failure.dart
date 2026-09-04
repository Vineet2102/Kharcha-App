/// Failure taxonomy per spec §9.7. Repositories map every exception to one
/// of these before it reaches the UI — a raw exception string is never shown
/// to the user.
sealed class Failure {
  const Failure(this.message);

  /// Human-readable, Indian-English message safe to show directly in the UI.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

final class NetworkFailure extends Failure {
  const NetworkFailure([
    super.message = 'No internet connection. Your changes are saved and will sync later.',
  ]);
}

final class AuthFailure extends Failure {
  const AuthFailure(super.message);
}

/// An RLS denial — the server rejected the request because of who the user is.
final class PermissionFailure extends Failure {
  const PermissionFailure([
    super.message = 'You do not have permission to do that.',
  ]);
}

final class ValidationFailure extends Failure {
  const ValidationFailure(super.message);
}

final class StorageFailure extends Failure {
  const StorageFailure([
    super.message = 'Could not save the receipt. Please try again.',
  ]);
}

final class UnknownFailure extends Failure {
  const UnknownFailure([
    super.message = 'Something went wrong. Please try again.',
  ]);
}
