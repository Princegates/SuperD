import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../models/delivery_status.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/staggered_list_item.dart';
import '../../../shared/widgets/status_badge.dart';
import '../providers/public_providers.dart';

/// A vendor's own order history - reachable only with their PRIVATE
/// `ordersCode` (`/vendor-orders/:ordersCode`), a separate secret from the
/// public link their customers use to place orders. No login required,
/// but this code is never shown to a customer - see
/// `0027_separate_vendor_orders_code.sql`.
class VendorOrdersScreen extends ConsumerWidget {
  const VendorOrdersScreen({super.key, required this.ordersCode});

  final String ordersCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesState = ref.watch(vendorDeliveriesProvider(ordersCode));

    return Scaffold(
      appBar: AppBar(title: const Text('Your orders')),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(vendorDeliveriesProvider(ordersCode)),
        child: AsyncValueView<List<VendorDelivery>>(
          value: deliveriesState,
          data: (orders) {
            if (orders.isEmpty) {
              return ListView(
                children: [
                  SizedBox(
                    height: 400,
                    child: Center(
                      child: Text(
                        'No orders yet',
                        style: TextStyle(color: Colors.grey.shade500),
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: orders.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => StaggeredListItem(
                key: ValueKey(orders[index].id),
                index: index,
                child: _OrderCard(order: orders[index]),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final VendorDelivery order;

  @override
  Widget build(BuildContext context) {
    final status = DeliveryStatus.fromString(order.status);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  '#${order.trackingCode}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                StatusBadge(status: status),
              ],
            ),
            const SizedBox(height: 8),
            Text('${order.customerName} · ${order.dropoffAddress}'),
            if (order.driverName != null) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: order.driverPhone == null
                    ? null
                    : () => launchPhoneCall(order.driverPhone!),
                child: Row(
                  children: [
                    const Icon(
                      Icons.delivery_dining,
                      size: 16,
                      color: Colors.black45,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      order.driverPhone != null
                          ? '${order.driverName} · ${order.driverPhone}'
                          : order.driverName!,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 6),
            Text(
              DateFormat('dd MMM, h:mm a').format(order.createdAt.toLocal()),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }
}
