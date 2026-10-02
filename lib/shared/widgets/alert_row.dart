import 'package:flutter/material.dart';

import '../../models/system_alert.dart';

/// One row of the Console Dashboard's unified alerts panel - see
/// `SystemAlert` and `alerts_providers.dart`. Tappable when the alert
/// carries a [SystemAlert.route] or [SystemAlert.sectionLabel]; otherwise
/// informational only.
class AlertRow extends StatelessWidget {
  const AlertRow({super.key, required this.alert, this.onTap});

  final SystemAlert alert;

  /// Called when this row is tapped and the alert carries a destination -
  /// the caller decides whether that means `context.push(route)` or
  /// jumping to a Console section by [SystemAlert.sectionLabel] (see
  /// `ConsoleDashboardTab`, which knows which is which).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(alert.icon, size: 15, color: color),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      alert.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alert.subtitle,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: Colors.grey.shade400,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
