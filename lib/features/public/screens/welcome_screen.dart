import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/legal/superd_legal_policy.dart';
import '../../../shared/utils/vendor_link.dart';

/// The app's actual front door - reachable at the bare root (`/`), before
/// any session/role check runs (see the `'/'` exemption in the router's
/// `redirect`). A Flutter-native equivalent of `web/welcome/index.html`
/// (still kept for linking from social media/ads - see the README's
/// "Marketing landing page" section), built this way instead of a
/// hosting-specific redirect so it's the first thing shown identically on
/// every host and in local dev (`flutter run`), not just on Netlify.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  static const _capabilities = [
    (Icons.bolt_outlined, 'Real-time dispatch'),
    (Icons.map_outlined, 'Live tracking'),
    (Icons.verified_outlined, 'Secure payments'),
  ];

  /// Drives the drifting logo watermark behind the content - one slow,
  /// looping clock the whole page reads its position off of.
  late final AnimationController _driftController;

  @override
  void initState() {
    super.initState();
    _driftController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    )..repeat();
  }

  @override
  void dispose() {
    _driftController.dispose();
    super.dispose();
  }

  /// Vendor registration and staff/driver login are their own separate
  /// journeys from this marketing page, so both open in a new tab on web
  /// (leaving this page open behind them) instead of navigating away from
  /// it in place. Native builds (no concept of "tabs") and the rare case
  /// where the app's own origin can't be determined both fall back to a
  /// normal in-app navigation instead.
  void _open(BuildContext context, String path) {
    final base = publicBaseUrl();
    if (kIsWeb && base.isNotEmpty) {
      launchUrl(Uri.parse('$base$path'), webOnlyWindowName: '_blank');
      return;
    }
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    // Below ~380dp (the narrowest common phones), the 42px wordmark and
    // 32px side padding this page was designed around don't leave enough
    // room for "SuperDelivery" to fit on one line - it was breaking
    // mid-word ("Deliver" / "y") instead of wrapping at a word boundary,
    // since the two TextSpans below have no space between them to break
    // on. Scaling both down together keeps the wordmark on one line on
    // every phone size actually in use, rather than fixing the symptom
    // (the break) without fixing the cause (not enough room).
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 380;
    final isCompact = screenWidth < 480;
    final titleFontSize = isNarrow ? 30.0 : (isCompact ? 36.0 : 42.0);
    final horizontalPadding = isNarrow ? 20.0 : 32.0;

    return Scaffold(
      backgroundColor: Colors.white,
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
                    AppTheme.accent.withValues(alpha: 0.10),
                    Colors.white,
                  ],
                ),
              ),
            ),
          ),
          _DriftingLogoShadow(controller: _driftController),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(
                    horizontal: horizontalPadding,
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
                          border: Border.all(color: const Color(0xFFE7EAEE)),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withValues(alpha: 0.14),
                              blurRadius: 26,
                              offset: const Offset(0, 12),
                            ),
                          ],
                        ),
                        child: Image.asset('assets/icon/icon.png'),
                      ),
                      const SizedBox(height: 36),
                      RichText(
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: GoogleFonts.poppins(
                            fontSize: titleFontSize,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.8,
                            height: 1.1,
                          ),
                          children: [
                            TextSpan(
                              text: 'Super',
                              style: TextStyle(color: AppTheme.primary),
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
                        'The delivery management platform built for local '
                        'businesses — seamlessly connecting vendors with '
                        'couriers from order to doorstep.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade700,
                          fontSize: isNarrow ? 14.5 : 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 40),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          _AnimatedCta(
                            glowColor: AppTheme.accent,
                            borderRadius: BorderRadius.circular(999),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 30,
                                  vertical: 17,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              onPressed: () => _open(context, '/vendor'),
                              child: const Text('Register your business'),
                            ),
                          ),
                          _AnimatedCta(
                            glowColor: AppTheme.primary,
                            borderRadius: BorderRadius.circular(999),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.primary,
                                side: BorderSide(
                                  color: AppTheme.primary.withValues(
                                    alpha: 0.35,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 26,
                                  vertical: 17,
                                ),
                                shape: const StadiumBorder(),
                                textStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                ),
                              ),
                              onPressed: () => _open(context, '/login'),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text('Driver and staff login'),
                                  SizedBox(width: 6),
                                  Icon(Icons.arrow_forward, size: 17),
                                ],
                              ),
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
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    color: Colors.grey.shade600,
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
                        style: GoogleFonts.inter(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: () => context.push('/legal/terms'),
                        child: Text(
                          'Terms & Privacy Policy',
                          style: GoogleFonts.inter(
                            color: Colors.grey.shade500,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: () => launchUrl(
                          Uri.parse('https://anknovate.com'),
                          webOnlyWindowName: '_blank',
                        ),
                        child: Text(
                          'Powered by $kOperatorLegalName',
                          style: GoogleFonts.inter(
                            color: Colors.grey.shade400,
                            fontSize: 12,
                          ),
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

/// A single large, low-opacity copy of the app mark, drifting slowly on a
/// gentle Lissajous-style path behind the page content with a soft sway -
/// "the logo moving in shadows," not a fully rendered logo competing with
/// the foreground. [controller] is the parent's single looping clock, kept
/// external so this stays a cheap [StatelessWidget] with no ticker of its
/// own - same pattern as [GlowOrbsBackground] elsewhere in the app.
class _DriftingLogoShadow extends StatelessWidget {
  const _DriftingLogoShadow({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value * 2 * math.pi;
            final dx = 0.5 + 0.16 * math.sin(t * 0.6);
            final dy = 0.4 + 0.09 * math.cos(t * 0.42);
            final angle = 0.07 * math.sin(t * 0.5);
            return Align(
              alignment: Alignment(dx * 2 - 1, dy * 2 - 1),
              child: Transform.rotate(
                angle: angle,
                child: Opacity(
                  opacity: 0.07,
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 620,
                    height: 620,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Wraps [child] (a call-to-action button) with a snappy hover/press
/// animation for desktop/web pointers - a small scale-up plus a soft glow
/// in [glowColor] on hover, and a quick scale-down on press. Purely
/// cosmetic on top of whatever the button already does on tap.
class _AnimatedCta extends StatefulWidget {
  const _AnimatedCta({
    required this.child,
    required this.glowColor,
    required this.borderRadius,
  });

  final Widget child;
  final Color glowColor;
  final BorderRadius borderRadius;

  @override
  State<_AnimatedCta> createState() => _AnimatedCtaState();
}

class _AnimatedCtaState extends State<_AnimatedCta> {
  bool _hovering = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scale = _pressed ? 0.96 : (_hovering ? 1.045 : 1.0);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() {
        _hovering = false;
        _pressed = false;
      }),
      child: Listener(
        onPointerDown: (_) => setState(() => _pressed = true),
        onPointerUp: (_) => setState(() => _pressed = false),
        onPointerCancel: (_) => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              borderRadius: widget.borderRadius,
              boxShadow: _hovering
                  ? [
                      BoxShadow(
                        color: widget.glowColor.withValues(alpha: 0.38),
                        blurRadius: 26,
                        spreadRadius: 1,
                      ),
                    ]
                  : const [],
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
