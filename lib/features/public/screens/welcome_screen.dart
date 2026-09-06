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

  static const _relaySteps = [
    (
      Icons.link,
      'A vendor shares a link',
      'One link goes out on WhatsApp, Instagram, or a storefront QR code '
          '— no app download for the customer.',
    ),
    (
      Icons.two_wheeler_outlined,
      'The nearest rider gets it',
      'The order is matched to a rider already working that zone, so '
          'pickup starts within minutes.',
    ),
    (
      Icons.task_alt,
      'Proof lands at the door',
      'A PIN confirms the handoff, and the vendor sees the delivery '
          'update live, the moment it happens.',
    ),
  ];

  /// Drives the drifting logo watermark behind the content - one slow,
  /// looping clock the whole page reads its position off of.
  late final AnimationController _driftController;

  /// Defaults to the visitor's actual local time of day, like the web
  /// welcome page's toggle; the button below lets them override it.
  late bool _isNightMode;

  @override
  void initState() {
    super.initState();
    final hour = DateTime.now().hour;
    _isNightMode = hour < 6 || hour >= 18;
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
    final isNight = _isNightMode;
    final palette = _Palette.of(isNight);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          // A single, static, understated glow behind the wordmark - not
          // the drifting multi-color orbs used on the splash screen. This
          // page is meant to read as a corporate product homepage, not a
          // playful loading moment. It fades to the night background color
          // instead of white when the toggle below switches modes - the
          // same "blended background" idea as the web welcome page's sky.
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 500),
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.5),
                  radius: 1.1,
                  colors: [
                    AppTheme.accent.withValues(alpha: isNight ? 0.16 : 0.10),
                    palette.background,
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
                      Align(
                        alignment: Alignment.centerRight,
                        child: _ModeToggleButton(
                          isNight: isNight,
                          onTap: () =>
                              setState(() => _isNightMode = !_isNightMode),
                        ),
                      ),
                      const SizedBox(height: 12),
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
                              style: TextStyle(color: palette.heading),
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
                          color: palette.body,
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
                            glowColor: palette.outlineForeground,
                            borderRadius: BorderRadius.circular(999),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: palette.outlineForeground,
                                side: BorderSide(color: palette.outlineBorder),
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
                              child: const Text('Driver and staff login'),
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
                                Icon(icon, size: 17, color: palette.muted),
                                const SizedBox(width: 8),
                                Text(
                                  label,
                                  style: GoogleFonts.inter(
                                    color: palette.muted,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 56),
                      Text(
                        'How it works',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 19,
                          color: isNight ? Colors.white : AppTheme.primary,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Column(
                        children: [
                          for (
                            var i = 0;
                            i < _relaySteps.length;
                            i++
                          ) ...[
                            _RelayStepRow(
                              step: _relaySteps[i],
                              palette: palette,
                            ),
                            if (i < _relaySteps.length - 1)
                              const Padding(
                                padding: EdgeInsets.only(left: 25),
                                child: _DashedConnector(),
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 48),
                      Text(
                        'About SuperDelivery',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: palette.heading,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'SuperDelivery is operated by $kOperatorLegalName, '
                        'connecting vendors, dispatchers, and independent '
                        "riders in one system - from a vendor's shareable "
                        'ordering link, through live GPS tracking and '
                        'Mobile Money payments, to PIN-verified proof of '
                        'delivery at the door.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: palette.body,
                          fontSize: 13.5,
                          height: 1.6,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 18,
                        runSpacing: 8,
                        children: [
                          GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse('mailto:$kOperatorContactEmail'),
                            ),
                            child: Text(
                              kOperatorContactEmail,
                              style: GoogleFonts.inter(
                                color: palette.link,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => launchUrl(
                              Uri.parse(
                                'tel:${kOperatorContactPhone.replaceAll(' ', '')}',
                              ),
                            ),
                            child: Text(
                              kOperatorContactPhone,
                              style: GoogleFonts.inter(
                                color: palette.link,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 40),
                      Text(
                        "Already a customer? Use the tracking link your "
                        'vendor sent you after you placed your order.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: palette.faint,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: () => context.push('/legal/terms'),
                        child: Text(
                          'Terms & Privacy Policy',
                          style: GoogleFonts.inter(
                            color: palette.muted,
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
                            color: palette.faint,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        // DateTime.now().year, not a literal - never goes
                        // stale on its own.
                        '© ${DateTime.now().year} $kOperatorLegalName. '
                        'All rights reserved.',
                        style: GoogleFonts.inter(
                          color: palette.faint,
                          fontSize: 11.5,
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

/// One row of the "How it works" relay: a hexagonal, gold-gradient badge
/// carrying the step's icon, next to its title and one-line description.
/// The hexagon echoes the speed-line motif in the app mark rather than a
/// plain numbered circle.
class _RelayStepRow extends StatelessWidget {
  const _RelayStepRow({required this.step, required this.palette});

  final (IconData, String, String) step;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final (icon, title, description) = step;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipPath(
          clipper: const _HexBadgeClipper(),
          child: Container(
            width: 50,
            height: 50,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.accent,
                  AppTheme.accent.withValues(alpha: 0.7),
                ],
              ),
            ),
            child: Icon(icon, color: Colors.black87, size: 22),
          ),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: palette.heading,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    color: palette.body,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A hexagon outline matching the app mark's speed-line badge shape, used
/// to clip each relay step's icon container.
class _HexBadgeClipper extends CustomClipper<Path> {
  const _HexBadgeClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * 0.5, 0)
      ..lineTo(w * 0.93, h * 0.25)
      ..lineTo(w * 0.93, h * 0.75)
      ..lineTo(w * 0.5, h)
      ..lineTo(w * 0.07, h * 0.75)
      ..lineTo(w * 0.07, h * 0.25)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// The short dashed line joining consecutive relay steps, echoing the
/// dashed connector used between steps on the static marketing page.
class _DashedConnector extends StatelessWidget {
  const _DashedConnector();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 2,
      height: 26,
      child: CustomPaint(painter: _DashedConnectorPainter()),
    );
  }
}

class _DashedConnectorPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.accent.withValues(alpha: 0.4)
      ..strokeWidth = 2;
    const dashHeight = 4.0;
    const dashSpace = 4.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(
        Offset(size.width / 2, y),
        Offset(size.width / 2, y + dashHeight),
        paint,
      );
      y += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The colors that flip between a light "day" look and a dark "night" one
/// - the Flutter counterpart to the toggle on `web/welcome/index.html`. The
/// gold accent and the icon card stay constant across both; everything
/// else adapts so text stays legible against either background. Built
/// fresh on every call (not cached) since [AppTheme.primary]/`.accent` are
/// mutable and can change if the app's theme preset does.
class _Palette {
  const _Palette({
    required this.background,
    required this.heading,
    required this.body,
    required this.muted,
    required this.faint,
    required this.link,
    required this.outlineForeground,
    required this.outlineBorder,
  });

  factory _Palette.of(bool isNight) {
    if (isNight) {
      return _Palette(
        background: const Color(0xFF0B1024),
        heading: Colors.white,
        body: Colors.white.withValues(alpha: 0.78),
        muted: Colors.white.withValues(alpha: 0.62),
        faint: Colors.white.withValues(alpha: 0.45),
        link: AppTheme.accent,
        outlineForeground: Colors.white,
        outlineBorder: Colors.white.withValues(alpha: 0.32),
      );
    }
    return _Palette(
      background: Colors.white,
      heading: Colors.black87,
      body: Colors.grey.shade700,
      muted: Colors.grey.shade600,
      faint: Colors.grey.shade400,
      link: AppTheme.primary,
      outlineForeground: AppTheme.primary,
      outlineBorder: AppTheme.primary.withValues(alpha: 0.35),
    );
  }

  final Color background;
  final Color heading;
  final Color body;
  final Color muted;
  final Color faint;
  final Color link;
  final Color outlineForeground;
  final Color outlineBorder;
}

/// The day/night switch itself - a small pill with a sliding sun/moon
/// thumb, matching the one in the nav bar of `web/welcome/index.html`.
class _ModeToggleButton extends StatelessWidget {
  const _ModeToggleButton({required this.isNight, required this.onTap});

  final bool isNight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Switch between day and night background',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 56,
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            color: isNight
                ? Colors.white.withValues(alpha: 0.07)
                : AppTheme.primary.withValues(alpha: 0.05),
            border: Border.all(
              color: isNight
                  ? Colors.white.withValues(alpha: 0.28)
                  : AppTheme.primary.withValues(alpha: 0.18),
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Icon(
                    Icons.wb_sunny_rounded,
                    size: 14,
                    color: isNight
                        ? Colors.white.withValues(alpha: 0.4)
                        : AppTheme.primary,
                  ),
                  Icon(
                    Icons.dark_mode_rounded,
                    size: 14,
                    color: isNight
                        ? AppTheme.accent
                        : AppTheme.primary.withValues(alpha: 0.35),
                  ),
                ],
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                alignment: isNight
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.accent,
                        AppTheme.accent.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
