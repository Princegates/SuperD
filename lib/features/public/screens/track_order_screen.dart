import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery_status.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/map_preview.dart';
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

  void _showTracking(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _LiveTrackingSheet(trackingCode: trackingCode),
    );
  }

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
                final canTrack =
                    status != DeliveryStatus.delivered &&
                    status != DeliveryStatus.cancelled &&
                    order.hasDriverLocation;
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
                          if (canTrack) ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: OutlinedButton.icon(
                                onPressed: () => _showTracking(context),
                                icon: const Icon(Icons.map_outlined, size: 16),
                                label: const Text('Track live'),
                              ),
                            ),
                          ],
                          if (status == DeliveryStatus.delivered) ...[
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            _RatingSection(
                              trackingCode: order.trackingCode,
                              initialRating: order.rating,
                              initialComment: order.ratingComment,
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

/// A live map of this one order, opened from the "Track live" button - "if
/// they want to", not shown by default. Keeps watching the same polling
/// provider ([trackedDeliveryProvider]) the order card behind it uses, so
/// the driver's position (and the order's status) update every ~5s while
/// this sheet is open. Mirrors `_TrackingSheet` in vendor_orders_screen.dart,
/// which does the same thing for a vendor watching one of their own orders.
class _LiveTrackingSheet extends ConsumerWidget {
  const _LiveTrackingSheet({required this.trackingCode});

  final String trackingCode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final order = ref.watch(trackedDeliveryProvider(trackingCode)).valueOrNull;

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
              order?.driverName != null
                  ? '${order!.driverName} is on the way'
                  : 'Waiting for a location update...',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 14),
            if (order?.hasDriverLocation ?? false) ...[
              MapPreview(
                pickup: LatLng(order!.driverLat!, order.driverLng!),
                dropoff: order.dropoffLat != null && order.dropoffLng != null
                    ? LatLng(order.dropoffLat!, order.dropoffLng!)
                    : null,
                height: 260,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => launchMapView(
                  lat: order.driverLat!,
                  lng: order.driverLng!,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in Google Maps'),
              ),
            ] else
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

/// A star rating for the driver on this one delivery - only shown once it's
/// delivered. [submitDeliveryRating] is an upsert (see
/// `0034_notifications_tracking_ratings.sql`), so re-opening this page after
/// already rating just pre-fills the stars/comment and lets the customer
/// change their mind.
class _RatingSection extends ConsumerStatefulWidget {
  const _RatingSection({
    required this.trackingCode,
    required this.initialRating,
    required this.initialComment,
  });

  final String trackingCode;
  final int? initialRating;
  final String? initialComment;

  @override
  ConsumerState<_RatingSection> createState() => _RatingSectionState();
}

class _RatingSectionState extends ConsumerState<_RatingSection> {
  late int _rating = widget.initialRating ?? 0;
  late final _commentController = TextEditingController(
    text: widget.initialComment ?? '',
  );
  bool _isSubmitting = false;
  String? _errorMessage;
  bool _submitted = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _errorMessage = 'Pick a star rating first.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(vendorRepositoryProvider)
          .submitDeliveryRating(
            trackingCode: widget.trackingCode,
            rating: _rating,
            comment: _commentController.text.trim().isEmpty
                ? null
                : _commentController.text.trim(),
          );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _submitted = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _errorMessage = 'Could not submit your rating. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExisting = widget.initialRating != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasExisting || _submitted
              ? 'Your rating of the rider'
              : 'Rate your rider',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (i) {
            final starIndex = i + 1;
            return IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() {
                _rating = starIndex;
                _errorMessage = null;
              }),
              icon: Icon(
                starIndex <= _rating ? Icons.star : Icons.star_border,
                color: AppTheme.warning,
                size: 28,
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _commentController,
          minLines: 1,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Comment (optional)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorMessage!,
            style: const TextStyle(color: AppTheme.danger, fontSize: 12),
          ),
        ],
        if (_submitted) ...[
          const SizedBox(height: 8),
          const Text(
            'Thanks for your feedback!',
            style: TextStyle(
              color: AppTheme.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    hasExisting || _submitted
                        ? 'Update rating'
                        : 'Submit rating',
                  ),
          ),
        ),
      ],
    );
  }
}
