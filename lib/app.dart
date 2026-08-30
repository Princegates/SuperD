import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/env.dart';
import 'core/providers/core_providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class SuperDApp extends ConsumerWidget {
  const SuperDApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.isConfigured) {
      return MaterialApp(
        title: 'SuperD',
        theme: AppTheme.light,
        home: const _MissingConfigScreen(),
      );
    }

    final router = ref.watch(routerProvider);
    final themeKey =
        ref.watch(appSettingsProvider).valueOrNull?.theme ?? 'navy_gold';
    AppTheme.apply(themeKey);

    // Push notification groundwork - registers this device against
    // whoever's signed in, and drops the registration on sign-out. See
    // PushNotificationService's doc comment: this is a no-op until an
    // actual Firebase project is wired up.
    ref.listen(currentProfileProvider, (previous, next) {
      final profile = next.valueOrNull;
      final pushService = ref.read(pushNotificationServiceProvider);
      if (profile != null) {
        pushService
            .initialize(
              onDeliveryNotificationTapped: (deliveryId) =>
                  ref.read(routerProvider).go('/driver/delivery/$deliveryId'),
            )
            .then((_) => pushService.registerDevice(profile.id));
      } else if (previous?.valueOrNull != null) {
        pushService.unregisterDevice();
      }

      // Tags a crash report with who hit it - just the profile id,
      // nothing that reads as personal data (no name/email/phone), so a
      // report can at least be traced to "which account" without this
      // becoming its own privacy concern. See the README's "Crash
      // reporting" section.
      Sentry.configureScope((scope) {
        scope.setUser(profile == null ? null : SentryUser(id: profile.id));
        scope.setTag('role', profile?.role.wireValue ?? 'signed_out');
      });
    });

    // AppTheme's colors are plain static fields (read directly all over the
    // app, not via Theme.of(context)), so changing them alone wouldn't
    // repaint anything already built. Keying the whole app on the theme
    // forces Flutter to tear down and rebuild every widget below it when a
    // super admin changes it - GoRouter's own state (the current route)
    // lives outside this widget tree, in the same `router` instance, so it
    // survives the remount and the user stays on the same screen.
    return MaterialApp.router(
      key: ValueKey('theme-$themeKey'),
      title: 'SuperD',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}

class _MissingConfigScreen extends StatelessWidget {
  const _MissingConfigScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'SuperD is not configured yet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Copy env.json.example to env.json, fill in your Supabase URL '
                'and anon key, then run with '
                '--dart-define-from-file=env.json. See README.md for the '
                'full self-hosting setup.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
