import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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

class DeliveryDetailDriverScreen extends ConsumerStatefulWidget {
  const DeliveryDetailDriverScreen({super.key, required this.deliveryId});

  final String deliveryId;

  @override
  ConsumerState<DeliveryDetailDriverScreen> createState() =>
      _DeliveryDetailDriverScreenState();
}

class _DeliveryDetailDriverScreenState
    extends ConsumerState<DeliveryDetailDriverScreen> {
  bool _isUndoing = false;

  Future<void> _undo(Delivery delivery, DeliveryStatus previous) async {
    setState(() => _isUndoing = true);
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .updateStatus(deliveryId: delivery.id, status: previous);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not undo. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUndoing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveryState = ref.watch(deliveryByIdProvider(widget.deliveryId));
    final delivery = deliveryState.valueOrNull;
    // "Reject" (only reachable from 'assigned') is a visible button on the
    // detail body itself, right next to "Accept & begin trip" - see
    // _DriverDetailBody. Undo stays tucked in this overflow menu since it's
    // a corrective action for every other status, not a step in the main
    // flow.
    final previousStatus = delivery?.status.previousForDriver;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery'),
        actions: [
          if (delivery != null && previousStatus != null)
            PopupMenuButton<VoidCallback>(
              enabled: !_isUndoing,
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: () => _undo(delivery, previousStatus),
                  child: Text('Undo - back to "${previousStatus.label}"'),
                ),
              ],
            ),
        ],
      ),
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
  bool _isRejecting = false;

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

  Future<void> _confirmReject() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject this delivery?'),
        content: const Text(
          "It'll go back to the pool, unassigned, for a dispatcher to give "
          'to another driver.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRejecting = true);
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .rejectDelivery(widget.delivery.id);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not reject this delivery. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isRejecting = false);
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
            child: delivery.status == DeliveryStatus.assigned
                // Before a driver has accepted, reject deserves equal
                // billing next to accept, not a buried menu item - it's a
                // real fork, not a correction.
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _isRejecting || _isUpdatingStatus
                                  ? null
                                  : _confirmReject,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.danger,
                                side: const BorderSide(color: AppTheme.danger),
                              ),
                              icon: _isRejecting
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.close),
                              label: const Text('Reject'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          if (nextStatus != null)
                            Expanded(
                              flex: 2,
                              child: ElevatedButton.icon(
                                onPressed: _isRejecting || _isUpdatingStatus
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
                      if (navigateTarget != null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () => launchNavigation(
                            lat: navigateTarget.latitude,
                            lng: navigateTarget.longitude,
                          ),
                          icon: const Icon(Icons.directions_outlined),
                          label: const Text('Navigate'),
                        ),
                      ],
                    ],
                  )
                : Row(
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
