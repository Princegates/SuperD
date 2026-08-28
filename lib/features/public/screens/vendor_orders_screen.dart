import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../models/delivery_status.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/map_preview.dart';
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
                child: _OrderCard(order: orders[index], ordersCode: ordersCode),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.ordersCode});

  final VendorDelivery order;
  final String ordersCode;

  void _showTracking(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _TrackingSheet(
        ordersCode: ordersCode,
        deliveryId: order.id,
        trackingCode: order.trackingCode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = DeliveryStatus.fromString(order.status);
    final canTrack =
        status != DeliveryStatus.delivered &&
        status != DeliveryStatus.cancelled &&
        order.hasDriverLocation;
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
            if (order.scheduledAt case final scheduledAt?) ...[
              const SizedBox(height: 4),
              Text(
                'Scheduled ${DateFormat('d MMM, h:mm a').format(scheduledAt)}',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
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
            if (canTrack) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => _showTracking(context),
                  icon: const Icon(Icons.map_outlined, size: 16),
                  label: const Text('Track'),
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

/// A live map of one active order, opened from the "Track" button - "if
/// they want to", not shown by default for every order. Keeps watching
/// the same polling provider the order list itself uses, so the driver's
/// position (and the order's status) update every ~5s while this sheet
/// is open, exactly as live as the list behind it.
class _TrackingSheet extends ConsumerWidget {
  const _TrackingSheet({
    required this.ordersCode,
    required this.deliveryId,
    required this.trackingCode,
  });

  final String ordersCode;
  final String deliveryId;
  final String trackingCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders =
        ref.watch(vendorDeliveriesProvider(ordersCode)).valueOrNull ?? [];
    VendorDelivery? current;
    for (final o in orders) {
      if (o.id == deliveryId) current = o;
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Tracking #$trackingCode',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              current?.driverName != null
                  ? '${current!.driverName} is on the way'
                  : 'Waiting for a location update...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            if (current?.hasDriverLocation ?? false)
              MapPreview(
                pickup: LatLng(current!.driverLat!, current.driverLng!),
                dropoff:
                    current.dropoffLat != null && current.dropoffLng != null
                    ? LatLng(current.dropoffLat!, current.dropoffLng!)
                    : null,
                height: 260,
              )
            else
              const SizedBox(
                height: 120,
                child: Center(child: Text('No live location yet')),
              ),
          ],
        ),
      ),
    );
  }
}
