import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/delivery.dart';
import '../utils/scheduled_delivery.dart';
import 'status_badge.dart';

class DeliveryCard extends StatefulWidget {
  const DeliveryCard({
    super.key,
    required this.delivery,
    required this.onTap,
    this.subtitle,
    this.fareText,
  });

  final Delivery delivery;
  final VoidCallback onTap;

  /// Optional extra line, e.g. the assigned driver's name on the admin view.
  final String? subtitle;

  /// Optional fare amount (e.g. "GHS 43.10") shown next to the customer/time
  /// row - used by the driver's "My Rides" screen; omitted everywhere else.
  final String? fareText;

  @override
  State<DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends State<DeliveryCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    final timeLabel = DateFormat.MMMd().add_jm().format(delivery.createdAt);
    final scheduledAt = delivery.scheduledAt;
    final isOverdue = delivery.isOverdue();
    final isDueSoon = delivery.isDueSoon(scheduledDueSoonThreshold);
    final scheduleColor = isOverdue ? AppTheme.danger : AppTheme.warning;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '#${delivery.trackingCode}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (delivery.autoAssigned) ...[
                    const SizedBox(width: 6),
                    const _AutoAssignedBadge(),
                  ],
                  if (delivery.isSpecial) ...[
                    const SizedBox(width: 6),
                    const _SpecialBadge(),
                  ],
                  const Spacer(),
                  StatusBadge(status: delivery.status),
                ],
              ),
              const SizedBox(height: 10),
              _AddressLine(
                icon: Icons.trip_origin,
                text: delivery.pickupAddress,
              ),
              const SizedBox(height: 4),
              _AddressLine(
                icon: Icons.place,
                text: delivery.dropoffAddress,
              ),
              if (scheduledAt != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    if (isDueSoon || isOverdue)
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) => Transform.scale(
                          scale: 1 + (_pulse.value * 0.25),
                          child: child,
                        ),
                        child: Icon(
                          Icons.alarm,
                          size: 13,
                          color: scheduleColor,
                        ),
                      )
                    else
                      Icon(
                        Icons.event_outlined,
                        size: 13,
                        color: Colors.grey.shade500,
                      ),
                    const SizedBox(width: 4),
                    Text(
                      'Scheduled ${DateFormat('d MMM, h:mm a').format(scheduledAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: (isDueSoon || isOverdue)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: (isDueSoon || isOverdue)
                            ? scheduleColor
                            : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 15,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      widget.subtitle ?? delivery.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    timeLabel,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (widget.fareText != null) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    widget.fareText!,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ).copyWith(color: AppTheme.primary),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill next to the tracking code marking a delivery whose current
/// driver was picked by the system automatically (same-zone matching at
/// creation, or a mid-trip auto-hand-off) rather than a dispatcher's own
/// choice - see [Delivery.autoAssigned].
class _AutoAssignedBadge extends StatelessWidget {
  const _AutoAssignedBadge();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Assigned automatically by the system, not a dispatcher',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.neutral.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bolt, size: 12, color: AppTheme.neutral),
            const SizedBox(width: 3),
            Text(
              'Auto',
              style: TextStyle(
                color: AppTheme.neutral,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small pill next to the tracking code marking a delivery a dispatcher
/// priced by hand instead of the usual zone pricing - see
/// [Delivery.isSpecial].
class _SpecialBadge extends StatelessWidget {
  const _SpecialBadge();

  @override
  Widget build(BuildContext context) {
    // Not const: AppTheme.accent is a mutable `static Color` (the active
    // theme preset can change at runtime), not a compile-time constant.
    return Tooltip(
      message: 'Priced by hand, not the usual zone pricing',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.star_outline, size: 12, color: AppTheme.accent),
            const SizedBox(width: 3),
            Text(
              'Special',
              style: TextStyle(
                color: AppTheme.accent,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressLine extends StatelessWidget {
  const _AddressLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5),
          ),
        ),
      ],
    );
  }
}
