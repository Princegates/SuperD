import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/env.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Clean paths on web (/v/CODE) instead of the default hash-based ones
  // (/#/v/CODE) - vendor/customer links depend on this.
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  if (Env.isConfigured) {
    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseAnonKey,
    );
  }

  // Crash/error reporting - see the README's "Crash reporting" section.
  // SentryFlutter.init() itself always runs (wrapping the whole app in
  // its zone is what catches an uncaught async error that would
  // otherwise vanish with nothing but a console log, exactly the kind
  // of thing that's historically only ever surfaced here as a user's
  // screenshot) - only sending anything anywhere depends on
  // Env.sentryDsn actually being set. Performance tracing is left off
  // (tracesSampleRate: 0) since this is only about catching crashes, not
  // profiling - keeps it within Sentry's free tier without configuring
  // anything extra.
  await SentryFlutter.init((options) {
    options.dsn = Env.sentryDsn;
    options.environment = kReleaseMode ? 'production' : 'development';
    options.tracesSampleRate = 0;
  }, appRunner: () => runApp(const ProviderScope(child: SuperDApp())));
}
