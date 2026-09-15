import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery_status.dart';
import '../../../models/vendor.dart';
import '../../../shared/widgets/live_eta.dart';
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
                // Not yet at a final state - worth keeping this page open
                // for, whether or not a rider's live position is on the
                // map yet (that's [canTrack] below).
                final isActive =
                    status != DeliveryStatus.delivered &&
                    status != DeliveryStatus.cancelled;
                final canTrack = isActive && order.hasDriverLocation;
                // Which leg the rider is on decides what an ETA even
                // means: before collection it is time to the shop, after
                // it is time to the door. Both are worth knowing, and
                // "assigned" is when someone watches this page hardest.
                final carryingIt =
                    status == DeliveryStatus.pickedUp ||
                    status == DeliveryStatus.inTransit;
                final etaDestLat = carryingIt
                    ? order.dropoffLat
                    : order.pickupLat;
                final etaDestLng = carryingIt
                    ? order.dropoffLng
                    : order.pickupLng;
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Card(
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
                          if (isActive) ...[
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Colors.grey.shade500,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Do not close this window to keep '
                                    'tracking your order.',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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
                          // The map goes on the page, not behind a
                          // button. Someone waiting for a parcel should
                          // not have to discover a control to see where
                          // their rider is - that was the whole point of
                          // sending them here.
                          if (canTrack) ...[
                            const SizedBox(height: 14),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: MapPreview(
                                pickup: LatLng(
                                  order.driverLat!,
                                  order.driverLng!,
                                ),
                                dropoff:
                                    order.dropoffLat != null &&
                                        order.dropoffLng != null
                                    ? LatLng(
                                        order.dropoffLat!,
                                        order.dropoffLng!,
                                      )
                                    : null,
                                height: 220,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                if (etaDestLat != null && etaDestLng != null)
                                  Flexible(
                                    child: LiveEta(
                                      originLat: order.driverLat!,
                                      originLng: order.driverLng!,
                                      destLat: etaDestLat,
                                      destLng: etaDestLng,
                                      positionUpdatedAt:
                                          order.driverLocationUpdatedAt,
                                      label: carryingIt
                                          ? 'Arriving in about'
                                          : 'Collecting in about',
                                    ),
                                  ),
                                const Spacer(),
                                TextButton.icon(
                                  onPressed: () => launchMapView(
                                    lat: order.driverLat!,
                                    lng: order.driverLng!,
                                  ),
                                  icon: const Icon(Icons.open_in_new, size: 15),
                                  label: const Text('Open in Maps'),
                                ),
                              ],
                            ),
                          ],
                          if (order.completionPin != null) ...[
                            const SizedBox(height: 16),
                            _PinCard(pin: order.completionPin!),
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
                      const SizedBox(height: 16),
                      const _VendorPromoCard(),
                    ],
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

/// A pitch to register as a vendor, shown to every customer tracking an
/// order - not just the ones already delivered. This is the moment
/// someone watching their own parcel move is most likely to think "I
/// could use this for my own business", so the ask sits right here
/// instead of only on the marketing site they'd have to go looking for
/// separately.
class _VendorPromoCard extends StatelessWidget {
  const _VendorPromoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primary, AppTheme.primary.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.storefront,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Run a business? Send deliveries like this one.',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Share one link with your customers and every order gets '
            'picked up, tracked live, and delivered - just like this one - '
            'with no delivery fleet of your own to manage.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/vendor'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.arrow_forward, size: 18),
              label: const Text(
                'Register your business',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
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
/// The delivery-completion PIN, shown once the rider has picked up the
/// package - the same one already texted/emailed at that point (see the
/// README's "Delivery-completion PIN" section), surfaced here too for a
/// customer who can't find that message. Hand this to the rider when
/// they arrive; server-side, `get_delivery_by_tracking_code()` only ever
/// returns it while the delivery is actually `picked_up`/`in_transit`.
class _PinCard extends StatelessWidget {
  const _PinCard({required this.pin});

  final String pin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'Give this PIN to your rider to confirm delivery',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.black54),
          ),
          const SizedBox(height: 6),
          Text(
            pin,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: AppTheme.primary,
            ),
          ),
        ],
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
