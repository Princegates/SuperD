import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import '../../models/payment_status.dart';
import '../providers/delivery_detail_providers.dart';

/// Shows the payment recorded for a delivery, if any, with a "Mark as
/// paid" action for whoever is allowed to record it (the database still
/// enforces this via RLS regardless of [canEdit]).
class PaymentCard extends ConsumerWidget {
  const PaymentCard({
    super.key,
    required this.deliveryId,
    required this.canEdit,
  });

  final String deliveryId;
  final bool canEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref
        .watch(paymentForDeliveryProvider(deliveryId))
        .valueOrNull;
    if (payment == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  payment.method.icon,
                  size: 18,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(width: 8),
                Text(
                  '${payment.currency} ${payment.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const Spacer(),
                _StatusChip(status: payment.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              payment.method.label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
            if (canEdit && payment.status != PaymentStatus.paid) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ref
                    .read(paymentRepositoryProvider)
                    .updateStatus(
                      paymentId: payment.id,
                      status: PaymentStatus.paid,
                    ),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Mark as paid'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final PaymentStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: status.color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
