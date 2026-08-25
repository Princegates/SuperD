import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Shows a brief, non-blocking checkmark + confetti burst over the current
/// screen — a small reward moment when a driver completes a delivery.
void showDeliveredCelebration(BuildContext context) {
  final overlay = Overlay.of(context);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) =>
        _DeliveredCelebrationOverlay(onDone: () => entry.remove()),
  );
  overlay.insert(entry);
}

class _Particle {
  _Particle({required this.angle, required this.distance, required this.color});
  final double angle;
  final double distance;
  final Color color;
}

class _DeliveredCelebrationOverlay extends StatefulWidget {
  const _DeliveredCelebrationOverlay({required this.onDone});

  final VoidCallback onDone;

  @override
  State<_DeliveredCelebrationOverlay> createState() =>
      _DeliveredCelebrationOverlayState();
}

class _DeliveredCelebrationOverlayState
    extends State<_DeliveredCelebrationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  late final List<_Particle> _particles = List.generate(14, (i) {
    final random = Random();
    final angle = (i / 14) * 2 * pi + random.nextDouble() * 0.3;
    final distance = 90 + random.nextDouble() * 50;
    const colors = [
      AppTheme.accent,
      AppTheme.primary,
      Colors.white,
      AppTheme.success,
    ];
    return _Particle(
      angle: angle,
      distance: distance,
      color: colors[i % colors.length],
    );
  });

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final t = _controller.value;

          final badgeScale = t < 0.3
              ? Curves.elasticOut.transform(t / 0.3)
              : 1.0;
          final fadeOutStart = t > 0.8 ? (t - 0.8) / 0.2 : 0.0;
          final badgeOpacity = (1 - fadeOutStart).clamp(0.0, 1.0);

          final particleProgress = ((t - 0.05) / 0.6).clamp(0.0, 1.0);
          final particleFadeStart = t > 0.6 ? (t - 0.6) / 0.4 : 0.0;
          final particleOpacity = (1 - particleFadeStart).clamp(0.0, 1.0);

          return Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.15 * badgeOpacity),
                ),
              ),
              Center(
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      for (final p in _particles)
                        Transform.translate(
                          offset: Offset(
                            cos(p.angle) *
                                p.distance *
                                Curves.easeOut.transform(particleProgress),
                            sin(p.angle) *
                                p.distance *
                                Curves.easeOut.transform(particleProgress),
                          ),
                          child: Opacity(
                            opacity: particleOpacity,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: p.color,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ),
                      Opacity(
                        opacity: badgeOpacity,
                        child: Transform.scale(
                          scale: badgeScale,
                          child: Container(
                            width: 96,
                            height: 96,
                            decoration: BoxDecoration(
                              color: AppTheme.success,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.success.withValues(
                                    alpha: 0.4,
                                  ),
                                  blurRadius: 24,
                                  spreadRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
