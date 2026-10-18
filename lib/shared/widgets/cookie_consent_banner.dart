import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// A one-time "we use cookies" notice for the web build, shown via
/// [MaterialBanner] through `app.dart`'s `scaffoldMessengerKey` - never a
/// custom-positioned overlay. An earlier version wrapped the whole app in
/// a `Stack` from `MaterialApp.router`'s `builder`, which depends on
/// getting that Stack's sizing exactly right; it didn't, and the deployed
/// web build rendered as a blank page. Driving Flutter's own
/// ScaffoldMessenger instead means this widget never touches the real
/// page's layout at all - [build] just returns [child] unchanged.
///
/// Native builds never show it: they don't touch a browser cookie jar at
/// all, only this device's own storage, which is covered by the main
/// Terms & Privacy Policy instead. See `superd_legal_policy.dart`'s
/// `kCookiePolicySections` for what's actually stored and why.
class CookieConsentBanner extends StatefulWidget {
  const CookieConsentBanner({
    super.key,
    required this.router,
    required this.scaffoldMessengerKey,
    required this.child,
  });

  final GoRouter router;
  final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey;
  final Widget child;

  @override
  State<CookieConsentBanner> createState() => _CookieConsentBannerState();
}

class _CookieConsentBannerState extends State<CookieConsentBanner> {
  static const _ackKey = 'superd_cookie_consent_ack';

  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) _maybeShow();
  }

  Future<void> _maybeShow() async {
    // initState re-runs across a theme-change remount (see app.dart's
    // ValueKey on MaterialApp.router) - only act on the first one.
    if (_attempted) return;
    _attempted = true;

    final prefs = await SharedPreferences.getInstance();
    if (!mounted || (prefs.getBool(_ackKey) ?? false)) return;

    // Wait for the first real frame so the ScaffoldMessenger this key
    // points at is actually mounted.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      final messenger = widget.scaffoldMessengerKey.currentState;
      if (messenger == null) return;
      messenger.showMaterialBanner(
        MaterialBanner(
          backgroundColor: const Color(0xFF13192B),
          leading: const Icon(Icons.info_outline, color: Colors.white70),
          content: const Text(
            "We use essential cookies and local storage to keep you "
            "signed in and verify you're not a bot on our public forms, "
            "plus a few on-device preferences. No advertising or "
            "tracking cookies.",
            style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => widget.router.push('/legal/cookies'),
              child: const Text(
                'Cookie Policy',
                style: TextStyle(color: Colors.white70),
              ),
            ),
            TextButton(
              onPressed: () async {
                messenger.hideCurrentMaterialBanner();
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool(_ackKey, true);
              },
              style: TextButton.styleFrom(foregroundColor: AppTheme.accent),
              child: const Text('Got it'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
