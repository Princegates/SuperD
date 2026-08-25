import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _entrance;
  late final AnimationController _pulse;

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

    _entrance.forward().whenComplete(() => _pulse.repeat(reverse: true));
  }

  @override
  void dispose() {
    _entrance.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: Listenable.merge([_entrance, _pulse]),
              builder: (context, child) {
                final pulseScale = 1.0 + (_pulse.value * 0.04);
                return Opacity(
                  opacity: _badgeFade.value,
                  child: Transform.scale(
                    scale: _badgeScale.value * pulseScale,
                    child: child,
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
                child: const Column(
                  children: [
                    Text(
                      'SuperD',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
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
              child: const SizedBox(
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
    );
  }
}
