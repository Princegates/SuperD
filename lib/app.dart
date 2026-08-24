import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/env.dart';
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

    return MaterialApp.router(
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
