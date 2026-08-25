import 'package:flutter/material.dart';

import '../../models/delivery_status.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});

  final DeliveryStatus status;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, animation) => ScaleTransition(
              scale: animation,
              child: FadeTransition(opacity: animation, child: child),
            ),
            child: Icon(
              status.icon,
              key: ValueKey(status),
              size: 14,
              color: status.color,
            ),
          ),
          const SizedBox(width: 5),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: status.color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            child: Text(status.label),
          ),
        ],
      ),
    );
  }
}
