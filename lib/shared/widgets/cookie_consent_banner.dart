import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/app_theme.dart';

/// A one-time "we use cookies" notice for the web build - wraps the whole
/// app via `app.dart`'s `MaterialApp.router(builder: ...)`. Native builds
/// never show it: they don't touch a browser cookie jar at all, only this
/// device's own storage, which is covered by the main Terms & Privacy
/// Policy instead. See `superd_legal_policy.dart`'s
/// `kCookiePolicySections` for what's actually stored and why.
///
/// `router` is passed in rather than looked up via `context` because this
/// widget sits in `builder`, outside the subtree GoRouter's own
/// `InheritedWidget` is scoped to - `app.dart` already has the instance
/// to hand (it reads `routerProvider` to build the app itself).
class CookieConsentBanner extends StatefulWidget {
  const CookieConsentBanner({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  State<CookieConsentBanner> createState() => _CookieConsentBannerState();
}

class _CookieConsentBannerState extends State<CookieConsentBanner> {
  static const _ackKey = 'superd_cookie_consent_ack';

  bool _ready = false;
  bool _acknowledged = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _load();
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _acknowledged = prefs.getBool(_ackKey) ?? false;
      _ready = true;
    });
  }

  Future<void> _acknowledge() async {
    setState(() => _acknowledged = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_ackKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final showBanner = kIsWeb && _ready && !_acknowledged;
    return Stack(
      children: [
        widget.child,
        if (showBanner)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              child: _ConsentBar(
                onViewPolicy: () => widget.router.push('/legal/cookies'),
                onAcknowledge: _acknowledge,
              ),
            ),
          ),
      ],
    );
  }
}

class _ConsentBar extends StatelessWidget {
  const _ConsentBar({required this.onViewPolicy, required this.onAcknowledge});

  final VoidCallback onViewPolicy;
  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      color: const Color(0xFF13192B),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final text = Text(
              "We use essential cookies and local storage to keep you "
              "signed in and verify you're not a bot on our public forms, "
              "plus a few on-device preferences. No advertising or "
              "tracking cookies.",
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.9),
                fontSize: 13,
                height: 1.4,
              ),
            );
            final actions = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onViewPolicy,
                  child: const Text(
                    'Cookie Policy',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
                const SizedBox(width: 4),
                ElevatedButton(
                  onPressed: onAcknowledge,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Got it'),
                ),
              ],
            );
            if (constraints.maxWidth < 560) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  text,
                  const SizedBox(height: 10),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: text),
                const SizedBox(width: 16),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
