import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/delivery_repository.dart'
    show TrackingLinkException;
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/profile.dart';
import '../../../models/staff_permission.dart';
import '../../../models/user_role.dart';
import '../../../models/zone.dart';
import '../../../shared/providers/delivery_detail_providers.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/map_preview.dart';
import '../../../shared/widgets/payment_card.dart';
import '../../../shared/widgets/status_badge.dart';
import '../providers/admin_providers.dart';

class DeliveryDetailAdminScreen extends ConsumerWidget {
  const DeliveryDetailAdminScreen({super.key, required this.deliveryId});

  final String deliveryId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Delivery delivery,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this delivery?'),
        content: Text(
          'This permanently erases delivery #${delivery.trackingCode} - '
          "its status history and recorded payment go with it. This can't "
          'be undone. To keep the record but stop it, cancel it instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Delete permanently',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(deliveryRepositoryProvider).deleteDelivery(delivery.id);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'delivery_deleted',
      entityType: 'delivery',
      entityId: delivery.id,
      summary: 'Deleted delivery #${delivery.trackingCode}',
    );
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveryState = ref.watch(deliveryByIdProvider(deliveryId));
    final isSuperAdmin =
        ref.watch(currentProfileProvider).valueOrNull?.role ==
        UserRole.superAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery'),
        actions: [
          if (isSuperAdmin)
            AsyncValueView<Delivery?>(
              value: deliveryState,
              data: (delivery) => delivery == null
                  ? const SizedBox.shrink()
                  : IconButton(
                      tooltip: 'Delete delivery',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _delete(context, ref, delivery),
                    ),
              loading: (_) => const SizedBox.shrink(),
              error: (_) => const SizedBox.shrink(),
            ),
        ],
      ),
      body: AsyncValueView<Delivery?>(
        value: deliveryState,
        onRetry: () => ref.invalidate(deliveryByIdProvider(deliveryId)),
        data: (delivery) {
          if (delivery == null) {
            return const Center(child: Text('Delivery not found'));
          }
          final drivers = ref.watch(
            rankedDriversProvider((
              pickupLat: delivery.pickupLat,
              pickupLng: delivery.pickupLng,
            )),
          );
          final zones = ref.watch(zonesProvider).valueOrNull ?? [];
          return _DetailBody(
            delivery: delivery,
            drivers: drivers,
            zones: zones,
          );
        },
      ),
    );
  }
}

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.delivery,
    required this.drivers,
    required this.zones,
  });

  final Delivery delivery;
  final List<Profile> drivers;
  final List<Zone> zones;

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
                    value: DateFormat('EEE d MMM, h:mm a').format(scheduledAt),
                  ),
              ],
            ),
          ),
        ),
        if (delivery.customerPhone?.isNotEmpty == true ||
            delivery.customerEmail?.isNotEmpty == true) ...[
          const SizedBox(height: 10),
          _ResendTrackingLinkButton(delivery: delivery),
        ],
        const SizedBox(height: 16),
        PaymentCard(deliveryId: delivery.id, canEdit: true),
        const SizedBox(height: 16),
        _AssignedDriverCard(delivery: delivery, drivers: drivers),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Zone',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Auto-detected from the drop-off location, or copied "
                  "from the vendor's own zone - correct it here if that "
                  "got it wrong.",
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  initialValue: delivery.zoneId,
                  decoration: const InputDecoration(labelText: 'Zone'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('No zone'),
                    ),
                    for (final zone in zones)
                      DropdownMenuItem<String?>(
                        value: zone.id,
                        child: Text(zone.name),
                      ),
                  ],
                  onChanged: (value) {
                    ref
                        .read(deliveryRepositoryProvider)
                        .setZone(deliveryId: delivery.id, zoneId: value);
                    final zoneName = value == null
                        ? 'No zone'
                        : zones.firstWhere((z) => z.id == value).name;
                    logAuditEvent(
                      ref.read(supabaseClientProvider),
                      action: 'zone_corrected',
                      entityType: 'delivery',
                      entityId: delivery.id,
                      summary:
                          'Set zone for delivery '
                          '#${delivery.trackingCode} to $zoneName',
                    );
                  },
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

/// Lets a dispatcher/super admin resend the customer's tracking link
/// (SMS/email) on demand - for when the original notify-delivery-events
/// message at creation never arrived. A `ConsumerStatefulWidget` of its
/// own, not folded into [_DetailBody], just so it can own a small
/// [_isSending] flag for its own loading state without touching the rest
/// of the (stateless) screen.
class _ResendTrackingLinkButton extends ConsumerStatefulWidget {
  const _ResendTrackingLinkButton({required this.delivery});

  final Delivery delivery;

  @override
  ConsumerState<_ResendTrackingLinkButton> createState() =>
      _ResendTrackingLinkButtonState();
}

class _ResendTrackingLinkButtonState
    extends ConsumerState<_ResendTrackingLinkButton> {
  bool _isSending = false;

  Future<void> _resend() async {
    setState(() => _isSending = true);
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .resendTrackingLink(widget.delivery.id);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'tracking_link_resent',
        entityType: 'delivery',
        entityId: widget.delivery.id,
        summary:
            'Resent tracking link for delivery '
            '#${widget.delivery.trackingCode}',
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Link resent')));
      }
    } on TrackingLinkException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not resend the link')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: _isSending ? null : _resend,
        icon: _isSending
            ? const SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.mark_email_unread_outlined, size: 18),
        label: const Text('Resend tracking link to customer'),
      ),
    );
  }
}

/// The driver dropdown on a delivery's detail page. A `ConsumerStatefulWidget`
/// rather than folded into [_DetailBody] because a rejected reassignment (see
/// [_assignDriver]) needs to force the dropdown to discard whatever the user
/// just picked and re-show the delivery's actual, unchanged driver -
/// `DropdownButtonFormField` keeps its own selection internally once picked,
/// it doesn't re-read `initialValue` on every rebuild, so [_resetCount] gives
/// it a new key to force that.
class _AssignedDriverCard extends ConsumerStatefulWidget {
  const _AssignedDriverCard({required this.delivery, required this.drivers});

  final Delivery delivery;
  final List<Profile> drivers;

  @override
  ConsumerState<_AssignedDriverCard> createState() =>
      _AssignedDriverCardState();
}

class _AssignedDriverCardState extends ConsumerState<_AssignedDriverCard> {
  int _resetCount = 0;

  /// Sets or clears the delivery's driver. Can be rejected server-side -
  /// see the cap check in `enforce_delivery_update()`
  /// (`0048_manual_assignment_cap.sql`) - if the target driver already
  /// has `app_settings.zone_auto_assign_cap` active deliveries.
  Future<void> _assignDriver(String? driverId) async {
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .assignDriver(deliveryId: widget.delivery.id, driverId: driverId);
    } on PostgrestException catch (e) {
      if (mounted) {
        setState(() => _resetCount++);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }

    final driverName = driverId == null
        ? 'Unassigned'
        : widget.drivers.firstWhere((d) => d.id == driverId).displayName;
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'driver_assigned',
      entityType: 'delivery',
      entityId: widget.delivery.id,
      summary:
          'Set driver for delivery #${widget.delivery.trackingCode} to '
          '$driverName',
    );
  }

  @override
  Widget build(BuildContext context) {
    final delivery = widget.delivery;
    final canAssign =
        ref.watch(currentProfileProvider).valueOrNull?.hasPermission(
              StaffPermission.assignDrivers,
            ) ??
        false;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Assigned driver',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade700,
                  ),
                ),
                if (delivery.autoAssigned &&
                    delivery.assignedDriverId != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.bolt, size: 14, color: AppTheme.neutral),
                  const SizedBox(width: 2),
                  Text(
                    'Auto-assigned by the system',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.neutral,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              key: ValueKey(_resetCount),
              initialValue: delivery.assignedDriverId,
              decoration: InputDecoration(
                labelText: 'Driver',
                helperText: canAssign
                    ? null
                    : "You don't have permission to assign drivers",
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Unassigned'),
                ),
                for (final driver in widget.drivers)
                  DropdownMenuItem<String?>(
                    value: driver.id,
                    child: Text(driver.displayName),
                  ),
              ],
              onChanged:
                  (delivery.status == DeliveryStatus.cancelled ||
                      delivery.status == DeliveryStatus.delivered ||
                      !canAssign)
                  ? null
                  : _assignDriver,
            ),
          ],
        ),
      ),
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
