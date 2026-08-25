import 'package:flutter/material.dart';

/// Text with a soft light band sweeping across it on a loop - a subtle
/// "futuristic" shimmer for a hero title, e.g. the splash screen's
/// wordmark. Purely decorative; falls back to plain [style] visually once
/// the shader is applied, just with a moving highlight.
class ShimmerText extends StatefulWidget {
  const ShimmerText({
    super.key,
    required this.text,
    required this.style,
    this.highlightColor = Colors.white,
  });

  final String text;
  final TextStyle style;
  final Color highlightColor;

  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.style.color ?? Colors.white;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final begin = Alignment.lerp(
          const Alignment(-2, 0),
          const Alignment(1, 0),
          _controller.value,
        )!;
        final end = Alignment.lerp(
          const Alignment(-1, 0),
          const Alignment(2, 0),
          _controller.value,
        )!;
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) => LinearGradient(
            colors: [baseColor, widget.highlightColor, baseColor],
            stops: const [0.35, 0.5, 0.65],
            begin: begin,
            end: end,
          ).createShader(bounds),
          child: child,
        );
      },
      child: Text(widget.text, style: widget.style),
    );
  }
}
