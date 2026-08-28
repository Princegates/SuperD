import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/providers/delivery_detail_providers.dart';
import '../providers/driver_providers.dart';
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
  bool _isCancelling = false;

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

  Future<void> _confirmCancel(Delivery delivery) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this trip?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "We'll try to hand it to another available driver right "
              "away. If nobody's free, it goes back to the unassigned "
              "pool and dispatch is alerted - either way, this is "
              "recorded against this delivery.",
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep this trip'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    final reason = reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .cancelTrip(delivery.id, reason: reason.isEmpty ? null : reason);
      // The realtime stream behind myDeliveriesProvider won't necessarily
      // deliver this delivery's own update - RLS re-evaluates against the
      // NEW row, and assigned_driver_id no longer matches this driver, so
      // Realtime has nothing to tell them (it's not a row they can still
      // see). A plain invalidate forces a fresh fetch, which correctly
      // excludes it - see the same note on rejectDelivery below.
      ref.invalidate(myDeliveriesProvider);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not cancel this trip. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveryState = ref.watch(deliveryByIdProvider(widget.deliveryId));
    final delivery = deliveryState.valueOrNull;
    // "Reject" (only reachable from 'assigned') is a visible button on the
    // detail body itself, right next to "Accept & begin trip" - see
    // _DriverDetailBody. Undo and "Cancel trip" (only reachable once
    // already accepted - picked_up/in_transit) stay tucked in this
    // overflow menu since neither is a step in the main flow - one's a
    // correction, the other's a rare exception, not the common path.
    final previousStatus = delivery?.status.previousForDriver;
    final canCancel =
        delivery?.status == DeliveryStatus.pickedUp ||
        delivery?.status == DeliveryStatus.inTransit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery'),
        actions: [
          if (delivery != null && (previousStatus != null || canCancel))
            PopupMenuButton<VoidCallback>(
              enabled: !_isUndoing && !_isCancelling,
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                if (previousStatus != null)
                  PopupMenuItem(
                    value: () => _undo(delivery, previousStatus),
                    child: Text('Undo - back to "${previousStatus.label}"'),
                  ),
                if (canCancel)
                  PopupMenuItem(
                    value: () => _confirmCancel(delivery),
                    child: const Text('Cancel trip'),
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
          // Same treatment as the dashboard list (see
          // DeliveryRepository.watchDriverDeliveries()) - this provider is
          // shared with the dispatcher/super-admin detail screen, which
          // still needs the real pickup details, so the masking happens
          // here rather than in the shared provider itself.
          return _DriverDetailBody(delivery: delivery.withPickupHiddenIfHistory);
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
      // Rejecting clears assigned_driver_id, so this driver's own RLS
      // read access to the row disappears in the same update - Supabase
      // Realtime checks RLS against the row's NEW state, so it never
      // delivers this change to a subscriber who can no longer see the
      // row, and myDeliveriesProvider's cached copy is left stuck at its
      // last-known (still-assigned) state instead of dropping it. A
      // plain invalidate forces a fresh REST fetch instead, which
      // re-applies RLS from scratch and correctly excludes it - the
      // dashboard doesn't have this problem for any other status change,
      // since only reject/cancel ever touch assigned_driver_id.
      ref.invalidate(myDeliveriesProvider);
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
    // A frozen driver (see is_frozen in
    // 0025_driver_categories_and_status.sql) can finish work already under
    // way, but can't accept something new - the server enforces this too,
    // this is just so the button doesn't invite a doomed tap.
    final isFrozen =
        ref.watch(currentProfileProvider).valueOrNull?.isFrozen ?? false;
    final acceptBlocked =
        delivery.status == DeliveryStatus.assigned && isFrozen;

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
                      if (delivery.scheduledAt case final scheduledAt?)
                        _InfoRow(
                          icon: Icons.event_outlined,
                          label: 'Scheduled',
                          value: DateFormat('EEE d MMM, h:mm a')
                              .format(scheduledAt),
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
                                onPressed:
                                    _isRejecting ||
                                        _isUpdatingStatus ||
                                        acceptBlocked
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
                      if (acceptBlocked) ...[
                        const SizedBox(height: 8),
                        const Text(
                          'Your account is frozen - contact dispatch before '
                          'accepting this.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
