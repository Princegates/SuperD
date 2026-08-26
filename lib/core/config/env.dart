/// Reads Supabase connection details supplied at build/run time via
/// `--dart-define-from-file=env.json` (or individual `--dart-define` flags).
///
/// See `env.json.example` at the repo root — copy it to `env.json` and fill
/// in the URL/anon key of your self-hosted (or hosted free-tier) Supabase
/// project. Compile-time config avoids bundling secrets as an app asset, so
/// `flutter test`/`flutter analyze` work with no setup at all.
class Env {
  Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');

  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  /// Optional: the URL this instance's *web* build is actually hosted at
  /// (e.g. `https://superd.example.com`), used to build vendor/customer
  /// links. Leave unset when running as a Flutter web build - it falls
  /// back to the browser's own address automatically. Set it when staff
  /// manage vendors from a non-web build (Android/iOS/desktop), since
  /// there the app has no real web address of its own to fall back to.
  static const String appBaseUrl = String.fromEnvironment('APP_BASE_URL');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
