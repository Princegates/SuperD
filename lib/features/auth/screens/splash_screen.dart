import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/glow_orbs_background.dart';
import '../../../shared/widgets/shimmer_text.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _pulse;
  late final AnimationController _ping;

  late final Animation<double> _badgeScale;
  late final Animation<double> _badgeFade;
  late final Animation<Offset> _textSlide;
  late final Animation<double> _textFade;
  late final Animation<double> _loaderFade;

  @override
  void initState() {
    super.initState();

    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _badgeScale = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
    ).drive(Tween(begin: 0.4, end: 1.0));

    _badgeFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.35, curve: Curves.easeOut),
    );

    _textSlide = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
    ).drive(Tween(begin: const Offset(0, 0.4), end: Offset.zero));

    _textFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
    );

    _loaderFade = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.7, 1.0, curve: Curves.easeOut),
    );

    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _ping = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();

    _entrance.forward().whenComplete(() => _pulse.repeat(reverse: true));
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    _ping.dispose();
    super.dispose();
  }

  Widget _radarRing(double t) {
    final size = 108 + t * 100;
    final opacity = (1 - t).clamp(0.0, 1.0) * 0.45;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: opacity),
          width: 1.6,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Stack(
        children: [
          Positioned.fill(
            child: GlowOrbsBackground(
              colors: [AppTheme.accent, Colors.white, AppTheme.accent],
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_entrance, _pulse, _ping]),
                  builder: (context, child) {
                    final pulseScale = 1.0 + (_pulse.value * 0.04);
                    return Opacity(
                      opacity: _badgeFade.value,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _radarRing(_ping.value),
                          _radarRing((_ping.value + 0.5) % 1.0),
                          Transform.scale(
                            scale: _badgeScale.value * pulseScale,
                            child: child,
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
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
                ),
                const SizedBox(height: 20),
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textFade,
                    child: Column(
                      children: [
                        ShimmerText(
                          text: 'SuperD',
                          highlightColor: AppTheme.accent,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Delivering more. Connecting better.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                FadeTransition(
                  opacity: _loaderFade,
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: AppTheme.accent,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
