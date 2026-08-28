import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

/// The app's actual front door - reachable at the bare root (`/`), before
/// any session/role check runs (see the `'/'` exemption in the router's
/// `redirect`). A Flutter-native equivalent of `web/welcome/index.html`
/// (still kept for linking from social media/ads - see the README's
/// "Marketing landing page" section), built this way instead of a
/// hosting-specific redirect so it's the first thing shown identically on
/// every host and in local dev (`flutter run`), not just on Netlify.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const _capabilities = [
    (Icons.bolt_outlined, 'Real-time dispatch'),
    (Icons.map_outlined, 'Live tracking'),
    (Icons.verified_outlined, 'Secure payments'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Stack(
        children: [
          // A single, static, understated glow behind the wordmark - not
          // the drifting multi-color orbs used on the splash screen. This
          // page is meant to read as a corporate product homepage, not a
          // playful loading moment.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.5),
                  radius: 1.1,
                  colors: [
                    AppTheme.accent.withValues(alpha: 0.16),
                    AppTheme.primary,
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 40,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Image.asset('assets/icon/icon.png'),
                      ),
                      const SizedBox(height: 36),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.5,
                            height: 1.1,
                          ),
                          children: [
                            const TextSpan(
                              text: 'Super',
                              style: TextStyle(color: Colors.white),
                            ),
                            TextSpan(
                              text: 'Delivery',
                              style: TextStyle(color: AppTheme.accent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'The delivery management platform for local '
                        'businesses - connecting vendors, dispatchers, and '
                        'riders from order to doorstep.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.72),
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 28,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: () => context.push('/vendor'),
                            child: const Text(
                              'Register your business',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 16,
                              ),
                            ),
                            onPressed: () => context.push('/login'),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Staff & driver login',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 15,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.arrow_forward, size: 17),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 56),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 32,
                        runSpacing: 16,
                        children: [
                          for (final (icon, label) in _capabilities)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  icon,
                                  size: 17,
                                  color: Colors.white.withValues(alpha: 0.5),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.6),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Text(
                        "Already a customer? Use the tracking link your "
                        'vendor sent you after you placed your order.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
