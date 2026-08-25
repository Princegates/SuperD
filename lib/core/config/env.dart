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

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
