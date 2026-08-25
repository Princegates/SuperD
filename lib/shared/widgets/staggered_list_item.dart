import 'package:flutter/material.dart';

/// Wraps a list item so it fades and slides up into place a little after
/// its neighbors, giving a list a lively "cascade" entrance instead of
/// popping in all at once. Delay is capped so long lists don't feel slow.
class StaggeredListItem extends StatefulWidget {
  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,
  });

  final int index;
  final Widget child;

  @override
  State<StaggeredListItem> createState() => _StaggeredListItemState();
}

class _StaggeredListItemState extends State<StaggeredListItem> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    final delayMs = 35 * widget.index.clamp(0, 10);
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSlide(
      offset: _visible ? Offset.zero : const Offset(0, 0.08),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: _visible ? 1 : 0,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
