import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/profile.dart';
import '../../../shared/providers/delivery_detail_providers.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/map_preview.dart';
import '../../../shared/widgets/payment_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../providers/admin_providers.dart';

class DeliveryDetailAdminScreen extends ConsumerWidget {
  const DeliveryDetailAdminScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveryState = ref.watch(deliveryByIdProvider(deliveryId));
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery')),
      body: AsyncValueView<Delivery?>(
        value: deliveryState,
        data: (delivery) {
          if (delivery == null) {
            return const Center(child: Text('Delivery not found'));
          }
          return _DetailBody(delivery: delivery, drivers: drivers);
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({required this.delivery, required this.drivers});

  final Delivery delivery;
  final List<Profile> drivers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pickup = delivery.hasPickupCoordinates
        ? LatLng(delivery.pickupLat!, delivery.pickupLng!)
        : null;
    final dropoff = delivery.hasDropoffCoordinates
        ? LatLng(delivery.dropoffLat!, delivery.dropoffLng!)
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              '#${delivery.trackingCode}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const Spacer(),
            StatusBadge(status: delivery.status),
          ],
        ),
        const SizedBox(height: 16),
        if (pickup != null || dropoff != null) ...[
          MapPreview(pickup: pickup, dropoff: dropoff, height: 200),
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.person_outline,
                  label: 'Customer',
                  value: delivery.customerName,
                ),
                if (delivery.customerPhone?.isNotEmpty == true)
                  _InfoRow(
                    icon: Icons.phone_outlined,
                    label: 'Phone',
                    value: delivery.customerPhone!,
                    onTap: () => launchPhoneCall(delivery.customerPhone!),
                  ),
                _InfoRow(
                  icon: Icons.trip_origin,
                  label: 'Pickup',
                  value: delivery.pickupAddress,
                ),
                _InfoRow(
                  icon: Icons.place_outlined,
                  label: 'Drop-off',
                  value: delivery.dropoffAddress,
                ),
                if (delivery.packageDescription?.isNotEmpty == true)
                  _InfoRow(
                    icon: Icons.inventory_2_outlined,
                    label: 'Package',
                    value: delivery.packageDescription!,
                  ),
                if (delivery.notes?.isNotEmpty == true)
                  _InfoRow(
                    icon: Icons.notes_outlined,
                    label: 'Notes',
                    value: delivery.notes!,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        PaymentCard(deliveryId: delivery.id, canEdit: true),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Assigned driver',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: delivery.assignedDriverId,
                  decoration: const InputDecoration(labelText: 'Driver'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    for (final driver in drivers)
                      DropdownMenuItem<String?>(
                        value: driver.id,
                        child: Text(driver.displayName),
                      ),
                  ],
                  onChanged: delivery.status == DeliveryStatus.cancelled
                      ? null
                      : (value) => ref
                            .read(deliveryRepositoryProvider)
                            .assignDriver(
                              deliveryId: delivery.id,
                              driverId: value,
                            ),
                ),
              ],
            ),
          ),
        ),
        if (delivery.proofOfDeliveryUrl != null) ...[
          const SizedBox(height: 16),
          Text(
            'Proof of delivery',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.network(
              delivery.proofOfDeliveryUrl!,
              fit: BoxFit.cover,
            ),
          ),
        ],
        const SizedBox(height: 24),
        if (delivery.status != DeliveryStatus.cancelled &&
            delivery.status != DeliveryStatus.delivered)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.danger),
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Cancel delivery?'),
                  content: const Text('This cannot be undone.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('No'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Yes, cancel'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await ref.read(deliveryRepositoryProvider).cancel(delivery.id);
              }
            },
            icon: const Icon(Icons.cancel_outlined),
            label: const Text('Cancel delivery'),
          ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade500),
            const SizedBox(width: 10),
            SizedBox(
              width: 72,
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
      ),
    );
  }
}
