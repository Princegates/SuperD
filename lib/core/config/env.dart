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

  /// Optional: a Sentry project DSN for crash/error reporting - see the
  /// README's "Crash reporting" section. Left empty, `SentryFlutter.init`
  /// still runs (so the rest of the app doesn't need to branch on this)
  /// but the SDK itself just doesn't send anything anywhere.
  static const String sentryDsn = String.fromEnvironment('SENTRY_DSN');

  /// Optional: a Cloudflare Turnstile site key (the public half of the
  /// pair - safe to embed in client code, unlike the secret key, which
  /// only ever lives server-side as an Edge Function secret) - see the
  /// README's "Public form protection" section. Left empty,
  /// [TurnstileWidget] renders nothing and the public forms submit
  /// without a token, same as before this existed.
  static const String turnstileSiteKey = String.fromEnvironment(
    'TURNSTILE_SITE_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
