class AppConstants {
  const AppConstants._();

  static const appName = 'Kharcha';
  static const defaultCurrencyCode = 'INR';
  static const timeZoneName = 'Asia/Kolkata';
  static const dbFileName = 'kharcha.sqlite';
  static const receiptsCacheDir = 'receipts';

  /// Spec §11.2: an expense (or income, same sanity bound) amount must be
  /// > 0 and ≤ ₹10,00,00,000.
  static const maxTransactionAmountPaise = 10000000000;
}
