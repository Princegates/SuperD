import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/providers/delivery_detail_providers.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivered_celebration.dart';
import '../../../shared/widgets/map_preview.dart';
import '../../../shared/widgets/payment_card.dart';
import '../../../shared/widgets/status_badge.dart';

class DeliveryDetailDriverScreen extends ConsumerWidget {
  const DeliveryDetailDriverScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveryState = ref.watch(deliveryByIdProvider(deliveryId));

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery')),
      body: AsyncValueView<Delivery?>(
        value: deliveryState,
        data: (delivery) {
          if (delivery == null) {
            return const Center(child: Text('Delivery not found'));
          }
          return _DriverDetailBody(delivery: delivery);
        },
      ),
    );
  }
}

class _DriverDetailBody extends ConsumerStatefulWidget {
  const _DriverDetailBody({required this.delivery});

  final Delivery delivery;

  @override
  ConsumerState<_DriverDetailBody> createState() => _DriverDetailBodyState();
}

class _DriverDetailBodyState extends ConsumerState<_DriverDetailBody> {
  bool _isUpdatingStatus = false;
  bool _isUploadingPhoto = false;

  Future<void> _advanceStatus(DeliveryStatus next) async {
    setState(() => _isUpdatingStatus = true);
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .updateStatus(deliveryId: widget.delivery.id, status: next);
      if (mounted && next == DeliveryStatus.delivered) {
        showDeliveredCelebration(context);
      }
    } finally {
      if (mounted) setState(() => _isUpdatingStatus = false);
    }
  }

  Future<void> _capturePhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (picked == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .uploadProofOfDelivery(
            deliveryId: widget.delivery.id,
            file: File(picked.path),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Could not upload photo')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    final pickup = delivery.hasPickupCoordinates
        ? LatLng(delivery.pickupLat!, delivery.pickupLng!)
        : null;
    final dropoff = delivery.hasDropoffCoordinates
        ? LatLng(delivery.dropoffLat!, delivery.dropoffLng!)
        : null;

    // Before the package is collected, a driver navigates to the pickup
    // point; once it's picked up, the destination switches to drop-off.
    // Once the job is over (delivered or cancelled) there's nowhere left
    // to navigate to, so the button goes away entirely rather than
    // pointing at a stale destination.
    final isTerminal =
        delivery.status == DeliveryStatus.delivered ||
        delivery.status == DeliveryStatus.cancelled;
    final navigateTarget = isTerminal
        ? null
        : (delivery.status == DeliveryStatus.assigned ||
                  delivery.status == DeliveryStatus.inTransit
              ? pickup
              : dropoff);
    final nextStatus = delivery.status.nextForDriver;
    final actionLabel = delivery.status == DeliveryStatus.assigned
        ? 'Accept & begin trip'
        : 'Mark ${nextStatus?.label}';

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#${delivery.trackingCode}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
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
                        'Proof of delivery',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (delivery.proofOfDeliveryUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            delivery.proofOfDeliveryUrl!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _isUploadingPhoto ? null : _capturePhoto,
                        icon: _isUploadingPhoto
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.camera_alt_outlined),
                        label: Text(
                          delivery.proofOfDeliveryUrl != null
                              ? 'Retake photo'
                              : 'Take photo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Row(
              children: [
                if (navigateTarget != null) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => launchNavigation(
                        lat: navigateTarget.latitude,
                        lng: navigateTarget.longitude,
                      ),
                      icon: const Icon(Icons.directions_outlined),
                      label: const Text('Navigate'),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                if (nextStatus != null)
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _isUpdatingStatus
                          ? null
                          : () => _advanceStatus(nextStatus),
                      icon: _isUpdatingStatus
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Icon(nextStatus.icon),
                      label: Text(actionLabel),
                    ),
                  ),
              ],
            ),
          ),
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
