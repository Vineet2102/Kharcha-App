/// Compile-time app configuration, per spec §5.6.
///
/// Never use `flutter_dotenv` here — it ships secrets as a readable asset.
/// Values are baked in at build time via `--dart-define-from-file`.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  /// Feature flag for the Realtime listener (spec §9.6 T-4.8). Realtime is
  /// always an optimisation on top of the poll-based sync engine, never a
  /// correctness requirement — disabling it must leave the app fully
  /// correct, just slower to notice a change made on another device.
  static const realtimeEnabled = bool.fromEnvironment(
    'REALTIME_ENABLED',
    defaultValue: true,
  );

  static bool get isValid =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void assertValid() {
    assert(
      supabaseUrl.isNotEmpty,
      'SUPABASE_URL missing — run with --dart-define-from-file=config/dev.json',
    );
    assert(
      supabaseAnonKey.isNotEmpty,
      'SUPABASE_ANON_KEY missing — run with --dart-define-from-file=config/dev.json',
    );
  }
}
