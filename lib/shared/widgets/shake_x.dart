import 'package:flutter/material.dart';

/// Shakes [child] horizontally whenever [trigger] changes to a non-null
/// value — used to give form errors a bit of physical feedback instead of
/// just quietly appearing as text.
class ShakeX extends StatefulWidget {
  const ShakeX({super.key, required this.trigger, required this.child});

  final Object? trigger;
  final Widget child;

  @override
  State<ShakeX> createState() => _ShakeXState();
}

class _ShakeXState extends State<ShakeX> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );
  late final Animation<double> _offset = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 0.0, end: -8.0), weight: 1),
    TweenSequenceItem(tween: Tween(begin: -8.0, end: 8.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 8.0, end: -6.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: -6.0, end: 4.0), weight: 2),
    TweenSequenceItem(tween: Tween(begin: 4.0, end: 0.0), weight: 1),
  ]).animate(_controller);

  @override
  void didUpdateWidget(covariant ShakeX oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.trigger != oldWidget.trigger && widget.trigger != null) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _offset,
      builder: (context, child) =>
          Transform.translate(offset: Offset(_offset.value, 0), child: child),
      child: widget.child,
    );
  }
}
