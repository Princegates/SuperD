import 'package:flutter/material.dart';

import '../../../core/theme/console_design.dart';

/// A small filled pill - active/inactive, a role name, a count - the
/// Console-wide equivalent of the ad-hoc colored `Container`/`Chip` each
/// tab built for itself (a vendor's active/deactivated tag, a driver's
/// frozen/pending tag, a role label in Team). Not for delivery status -
/// that stays `StatusBadge`, shared with the driver app.
class ConsoleBadge extends StatelessWidget {
  const ConsoleBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.outlined = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;

  /// A quieter outline-only style for a secondary/less urgent tag,
  /// alongside a filled one for the thing that actually needs attention
  /// (e.g. "Frozen" filled red beside an outlined "Driver").
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = color ?? ConsoleColors.inkMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: outlined ? Border.all(color: c.withValues(alpha: 0.4)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: c),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}
