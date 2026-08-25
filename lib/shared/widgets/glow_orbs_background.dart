import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Soft, slowly drifting glow orbs used as a decorative background for a
/// "futuristic" feel behind the splash/login screens. Purely cosmetic -
/// place behind content in a [Stack]; ignores touches so it never steals
/// taps from whatever sits on top of it.
class GlowOrbsBackground extends StatefulWidget {
  const GlowOrbsBackground({super.key, required this.colors});

  /// At least one color; up to three are used, one per orb.
  final List<Color> colors;

  @override
  State<GlowOrbsBackground> createState() => _GlowOrbsBackgroundState();
}

class _GlowOrbsBackgroundState extends State<GlowOrbsBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _colorAt(int index) =>
      widget.colors[math.min(index, widget.colors.length - 1)];

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final t = _controller.value * 2 * math.pi;
            return Stack(
              children: [
                _orb(
                  color: _colorAt(0),
                  size: 260,
                  dx: 0.18 + 0.10 * math.sin(t),
                  dy: 0.15 + 0.07 * math.cos(t * 0.8),
                ),
                _orb(
                  color: _colorAt(1),
                  size: 220,
                  dx: 0.82 + 0.08 * math.cos(t * 0.65),
                  dy: 0.3 + 0.09 * math.sin(t * 1.1),
                ),
                _orb(
                  color: _colorAt(2),
                  size: 320,
                  dx: 0.5 + 0.12 * math.sin(t * 0.5 + 1),
                  dy: 0.88 + 0.06 * math.cos(t * 0.9),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _orb({
    required Color color,
    required double size,
    required double dx,
    required double dy,
  }) {
    return Align(
      alignment: Alignment(dx * 2 - 1, dy * 2 - 1),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.32), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}
