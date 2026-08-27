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
  });

  final Delivery delivery;
  final VoidCallback onTap;

  /// Optional extra line, e.g. the assigned driver's name on the admin view.
  final String? subtitle;

  @override
  State<DeliveryCard> createState() => _DeliveryCardState();
}

class _DeliveryCardState extends State<DeliveryCard>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

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

    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Card(
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
                ],
              ),
            ),
          ),
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
