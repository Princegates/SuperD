import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/delivery_failure_reason.dart';
import '../../models/delivery_status.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status, this.failureReason});

  final DeliveryStatus status;

  /// Set on a delivery that was ridden for and did not complete. Both
  /// that and a dispatcher calling an order off are stored as
  /// `cancelled` (see `0089_failed_delivery_outcome.sql`), so without
  /// this the badge would report them as the same thing - which is
  /// exactly the confusion the failure outcome exists to end.
  final DeliveryFailureReason? failureReason;

  @override
  Widget build(BuildContext context) {
    final failure = failureReason;
    final color = failure == null ? status.color : AppTheme.warning;
    final icon = failure == null ? status.icon : Icons.report_problem_outlined;
    final label = failure == null ? status.label : 'Failed';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
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
              icon,
              key: ValueKey('$status/$failure'),
              size: 14,
              color: color,
            ),
          ),
          const SizedBox(width: 5),
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
            child: Text(label),
          ),
        ],
      ),
    );
  }
}
