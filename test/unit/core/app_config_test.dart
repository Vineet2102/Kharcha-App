import 'package:flutter_test/flutter_test.dart';

import 'package:kharcha/core/config/app_config.dart';

/// A plain `flutter test` run has no `--dart-define-from-file`, so
/// `SUPABASE_URL`/`SUPABASE_ANON_KEY` are empty — exactly the "not
/// configured" state this file's own asserts guard against.
void main() {
  test('appEnv defaults to "dev" and realtimeEnabled defaults to true when '
      'not overridden by a --dart-define', () {
    expect(AppConfig.appEnv, 'dev');
    expect(AppConfig.realtimeEnabled, isTrue);
  });

  test(
    'isValid is false when no Supabase config was baked in at build time',
    () {
      expect(AppConfig.supabaseUrl, isEmpty);
      expect(AppConfig.supabaseAnonKey, isEmpty);
      expect(AppConfig.isValid, isFalse);
    },
  );

  test('assertValid throws in a debug/test build when config is missing', () {
    expect(AppConfig.assertValid, throwsA(isA<AssertionError>()));
  });
}
