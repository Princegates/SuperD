import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/delivery.dart';
import 'status_badge.dart';

class DeliveryCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final timeLabel = DateFormat.MMMd().add_jm().format(delivery.createdAt);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
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
              _AddressLine(icon: Icons.trip_origin, text: delivery.pickupAddress),
              const SizedBox(height: 4),
              _AddressLine(icon: Icons.place, text: delivery.dropoffAddress),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.person_outline, size: 15, color: Colors.grey.shade600),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      subtitle ?? delivery.customerName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                    ),
                  ),
                  Text(
                    timeLabel,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                  ),
                ],
              ),
            ],
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
