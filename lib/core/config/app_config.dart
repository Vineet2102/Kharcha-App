/// Compile-time app configuration, per spec §5.6.
///
/// Never use `flutter_dotenv` here — it ships secrets as a readable asset.
/// Values are baked in at build time via `--dart-define-from-file`.
class AppConfig {
  const AppConfig._();

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const appEnv = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

  static bool get isValid => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

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
