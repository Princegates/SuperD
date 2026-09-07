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
    with TickerProviderStateMixin {
  static const _waybillSteps = [
    (
      'Vendor shares a link',
      'Register once and get a link that turns into a delivery form for '
          "your own customers - no account needed on either side.",
    ),
    (
      'Nearest rider gets it',
      'Priced automatically from real road distance and matched to an '
          "available rider in the same zone the moment it's placed.",
    ),
    (
      'Proof lands at the door',
      'Customer and vendor both watch it live, and a one-time PIN '
          'confirms it actually arrived.',
    ),
  ];

  /// Drives the drifting logo watermark behind the content - one slow,
  /// looping clock the whole page reads its position off of.
  late final AnimationController _driftController;

  /// Drives the rider dot travelling the route in the hero panel below -
  /// the Flutter counterpart to the CSS `offset-path` animation on
  /// `web/welcome/index.html`'s own route illustration.
  late final AnimationController _routeController;

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
    _routeController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _driftController.dispose();
    _routeController.dispose();
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
    // Scales the headline and side padding down on narrower phones, so the
    // multi-line hero statement below keeps a comfortable line length
    // instead of cramming against the edges.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isNarrow = screenWidth < 380;
    final isCompact = screenWidth < 480;
    final titleFontSize = isNarrow ? 26.0 : (isCompact ? 30.0 : 36.0);
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
                      // A small nav-style row - icon mark, wordmark, and the
                      // day/night toggle - instead of a large centered logo,
                      // so the big headline right below carries the hero
                      // moment. Mirrors the nav bar on web/welcome/index.html.
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.asset(
                                  'assets/icon/icon.png',
                                  width: 28,
                                  height: 28,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'SuperDelivery',
                                style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: palette.heading,
                                ),
                              ),
                            ],
                          ),
                          _ModeToggleButton(
                            isNight: isNight,
                            onTap: () =>
                                setState(() => _isNightMode = !_isNightMode),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      _RouteMapPanel(
                        controller: _routeController,
                        palette: palette,
                      ),
                      const SizedBox(height: 36),
                      Text(
                        'Turn your shop into a delivery business.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontSize: titleFontSize,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          height: 1.15,
                          color: palette.heading,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Share one link. A rider nearby picks it up, the '
                        'order is tracked live, and a PIN confirms it '
                        'arrived - paid straight to your Mobile Money.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: palette.body,
                          fontSize: isNarrow ? 14.5 : 16,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _AnimatedCta(
                            glowColor: AppTheme.accent,
                            borderRadius: BorderRadius.circular(10),
                            child: FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.black,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 26,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              onPressed: () => _open(context, '/vendor'),
                              child: const Text('Register your business'),
                            ),
                          ),
                          _AnimatedCta(
                            glowColor: palette.heading,
                            borderRadius: BorderRadius.circular(10),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: palette.heading,
                                side: BorderSide(
                                  color: palette.border,
                                  width: 1.5,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 15,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                textStyle: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14.5,
                                ),
                              ),
                              onPressed: () => _open(context, '/login'),
                              child: const Text('Driver and staff login'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 56),
                      Text(
                        'One link, three people, no back and forth',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w800,
                          fontSize: 21,
                          letterSpacing: -0.5,
                          color: palette.heading,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Everything after the link is handled - here's the "
                        'whole trip.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: palette.body,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Container(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          border: Border.all(color: palette.border),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 8,
                        ),
                        child: Column(
                          children: [
                            for (
                              var i = 0;
                              i < _waybillSteps.length;
                              i++
                            ) ...[
                              _WaybillStub(
                                index: i + 1,
                                step: _waybillSteps[i],
                                palette: palette,
                              ),
                              if (i < _waybillSteps.length - 1)
                                _DashedDivider(color: palette.border),
                            ],
                          ],
                        ),
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

/// One stub of the "How it works" waybill: a stamped step number next to
/// its title and description, echoing the perforated-ticket strip on
/// `web/welcome/index.html`. Numbered because this genuinely is a
/// 3-step sequence, not a decorative counter.
class _WaybillStub extends StatelessWidget {
  const _WaybillStub({
    required this.index,
    required this.step,
    required this.palette,
  });

  final int index;
  final (String, String) step;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    final (title, description) = step;
    // Alternates the stamp's tilt per step, like a hand-stamped ticket -
    // matches the web page's :nth-child rotation.
    final tilt = const [-0.10, 0.07, -0.05][(index - 1) % 3];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.rotate(
            angle: tilt,
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.accent, width: 2),
              ),
              child: Text(
                '$index',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: AppTheme.accent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 15.5,
              color: palette.heading,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: GoogleFonts.inter(
              color: palette.body,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}

/// The perforated-looking dashed rule between waybill stubs.
class _DashedDivider extends StatelessWidget {
  const _DashedDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, 1),
            painter: _DashedLinePainter(color: color),
          );
        },
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    const dashWidth = 5.0;
    const dashSpace = 5.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dashWidth, 0), paint);
      x += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The hero's live-route illustration: a shop pin and a doorstep pin
/// joined by a dashed route, with a rider dot travelling it on a loop -
/// the literal mechanic of the product (an order finding a nearby rider
/// and reaching a door), matching the animated route on
/// `web/welcome/index.html`'s own hero.
class _RouteMapPanel extends StatelessWidget {
  const _RouteMapPanel({required this.controller, required this.palette});

  final AnimationController controller;
  final _Palette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 220,
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.infinite,
            painter: _RoutePainter(
              t: controller.value,
              gridColor: palette.border,
              pinColor: palette.heading,
              gold: AppTheme.accent,
            ),
          );
        },
      ),
    );
  }
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.t,
    required this.gridColor,
    required this.pinColor,
    required this.gold,
  });

  final double t;
  final Color gridColor;
  final Color pinColor;
  final Color gold;

  static const _p0 = Offset(30, 150);
  static const _p1 = Offset(80, 40);
  static const _p2 = Offset(160, 200);
  static const _p3 = Offset(270, 50);

  Offset _cubicBezier(double t) {
    final mt = 1 - t;
    final x = mt * mt * mt * _p0.dx +
        3 * mt * mt * t * _p1.dx +
        3 * mt * t * t * _p2.dx +
        t * t * t * _p3.dx;
    final y = mt * mt * mt * _p0.dy +
        3 * mt * mt * t * _p1.dy +
        3 * mt * t * t * _p2.dy +
        t * t * t * _p3.dy;
    return Offset(x, y);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += size.width / 4) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += size.height / 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // The route itself is drawn in a fixed 300x200 space and centered
    // within whatever the panel's actual size turns out to be, while the
    // grid above already spans the full panel.
    const contentWidth = 300.0;
    const contentHeight = 200.0;
    canvas.save();
    canvas.translate(
      (size.width - contentWidth) / 2,
      (size.height - contentHeight) / 2,
    );

    final zonePaint = Paint()..color = gold.withValues(alpha: 0.07);
    canvas.drawCircle(_p0, 70, zonePaint);
    canvas.drawCircle(_p3, 70, zonePaint);

    final pathPaint = Paint()
      ..color = gold
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    const steps = 60;
    for (var i = 0; i < steps; i += 2) {
      final a = _cubicBezier(i / steps);
      final b = _cubicBezier((i + 1) / steps);
      canvas.drawLine(a, b, pathPaint);
    }

    final pinPaint = Paint()..color = pinColor;
    canvas.drawCircle(_p0, 6, pinPaint);
    canvas.drawCircle(_p3, 6, pinPaint);

    final textStyle = TextStyle(
      color: pinColor,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      fontFamily: 'Inter',
    );
    _drawLabel(canvas, 'Shop', _p0 + const Offset(0, 14), textStyle);
    _drawLabel(canvas, 'Doorstep', _p3 + const Offset(0, -26), textStyle);

    final riderCenter = _cubicBezier(t);
    final ringPaint = Paint()
      ..color = gold.withValues(alpha: 0.4)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(riderCenter, 11, ringPaint);
    canvas.drawCircle(riderCenter, 5.5, Paint()..color = gold);
    canvas.restore();
  }

  void _drawLabel(Canvas canvas, String text, Offset center, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center - Offset(painter.width / 2, 0));
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) =>
      oldDelegate.t != t;
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
    required this.surface,
    required this.border,
    required this.heading,
    required this.body,
    required this.muted,
    required this.faint,
    required this.link,
  });

  factory _Palette.of(bool isNight) {
    if (isNight) {
      return _Palette(
        background: const Color(0xFF0F1424),
        surface: const Color(0xFF182036),
        border: Colors.white.withValues(alpha: 0.12),
        heading: const Color(0xFFF3F1EC),
        body: const Color(0xFFF3F1EC).withValues(alpha: 0.78),
        muted: const Color(0xFFF3F1EC).withValues(alpha: 0.64),
        faint: const Color(0xFFF3F1EC).withValues(alpha: 0.45),
        link: AppTheme.accent,
      );
    }
    return _Palette(
      background: const Color(0xFFFBF9F5),
      surface: Colors.white,
      border: const Color(0xFFE7E2D8),
      heading: const Color(0xFF1B2130),
      body: Colors.grey.shade700,
      muted: const Color(0xFF6B7280),
      faint: Colors.grey.shade400,
      link: AppTheme.primary,
    );
  }

  final Color background;
  final Color surface;
  final Color border;
  final Color heading;
  final Color body;
  final Color muted;
  final Color faint;
  final Color link;
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
