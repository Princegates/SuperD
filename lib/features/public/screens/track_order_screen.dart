import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/delivery_status.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/status_badge.dart';
import '../providers/public_providers.dart';

/// A customer's own order-tracking page, reachable at `/t/:trackingCode` -
/// the tracking code they were given right after submitting a request.
/// Deliberately scoped to just this one delivery (see
/// `get_delivery_by_tracking_code()`), never the vendor's full order list -
/// a customer has no way to see anyone else's order through this page.
class TrackOrderScreen extends ConsumerWidget {
  const TrackOrderScreen({super.key, required this.trackingCode});

  final String trackingCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderState = ref.watch(trackedDeliveryProvider(trackingCode));

    return Scaffold(
      appBar: AppBar(title: Text('Order #$trackingCode')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AsyncValueView<VendorDelivery?>(
              value: orderState,
              data: (order) {
                if (order == null) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "We couldn't find an order with this tracking code.",
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                final status = DeliveryStatus.fromString(order.status);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '#${order.trackingCode}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              StatusBadge(status: status),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _Row(
                            icon: Icons.place_outlined,
                            label: 'Drop-off',
                            value: order.dropoffAddress,
                          ),
                          if (order.scheduledAt case final scheduledAt?) ...[
                            const SizedBox(height: 10),
                            _Row(
                              icon: Icons.event_outlined,
                              label: 'Scheduled',
                              value: DateFormat('EEE d MMM, h:mm a')
                                  .format(scheduledAt),
                            ),
                          ],
                          if (order.driverName != null) ...[
                            const SizedBox(height: 10),
                            _Row(
                              icon: Icons.delivery_dining,
                              label: 'Rider',
                              value: order.driverPhone != null
                                  ? '${order.driverName} · ${order.driverPhone}'
                                  : order.driverName!,
                              onTap: order.driverPhone == null
                                  ? null
                                  : () => launchPhoneCall(order.driverPhone!),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Placed ${DateFormat('dd MMM, h:mm a').format(order.createdAt.toLocal())}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: onTap != null ? AppTheme.primary : Colors.black87,
                fontWeight: onTap != null ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
