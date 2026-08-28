import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glow_orbs_background.dart';

/// The app's actual front door - reachable at the bare root (`/`), before
/// any session/role check runs (see the `'/'` exemption in the router's
/// `redirect`). A Flutter-native equivalent of `web/welcome/index.html`
/// (still kept for linking from social media/ads - see the README's
/// "Marketing landing page" section), built this way instead of a
/// hosting-specific redirect so it's the first thing shown identically on
/// every host and in local dev (`flutter run`), not just on Netlify.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Stack(
        children: [
          Positioned.fill(
            child: GlowOrbsBackground(
              colors: [Colors.white24, AppTheme.accent, AppTheme.accent],
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 108,
                        height: 108,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.35),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Image.asset('assets/icon/icon.png'),
                      ),
                      const SizedBox(height: 28),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
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
                      const SizedBox(height: 12),
                      const Text(
                        'Delivering More. Connecting Better. — a free, '
                        'open-source delivery management platform for local '
                        'vendors, their dispatchers, and the riders who get '
                        'it there.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, height: 1.4),
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.accent,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () => context.push('/vendor'),
                            child: const Text(
                              'Register your business',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 16,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                            ),
                            onPressed: () => context.push('/login'),
                            child: const Text(
                              'Staff & driver login',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        "Already a customer? Use the tracking link your "
                        'vendor sent you after you placed your order.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white54, fontSize: 13),
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
