import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery_status.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/ghana_phone.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/location_field.dart';
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

  void _requestSpecialDelivery(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _SpecialRequestSheet(ordersCode: ordersCode),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesState = ref.watch(vendorDeliveriesProvider(ordersCode));

    return Scaffold(
      appBar: AppBar(title: const Text('Your orders')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _requestSpecialDelivery(context),
        icon: const Icon(Icons.add_circle_outline),
        label: const Text('Special delivery'),
      ),
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

/// A vendor asking dispatch for a hand-priced special delivery, from their
/// own private orders page - no fee field here on purpose. See
/// `submitSpecialDeliveryRequest` in `VendorRepository`: a dispatcher
/// prices and creates the real delivery afterward, the same as when this
/// gets phoned in instead.
class _SpecialRequestSheet extends ConsumerStatefulWidget {
  const _SpecialRequestSheet({required this.ordersCode});

  final String ordersCode;

  @override
  ConsumerState<_SpecialRequestSheet> createState() =>
      _SpecialRequestSheetState();
}

class _SpecialRequestSheetState extends ConsumerState<_SpecialRequestSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _packageController = TextEditingController();
  final _notesController = TextEditingController();

  double? _lat;
  double? _lng;
  bool _isSubmitting = false;
  bool _isSent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _packageController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref
          .read(vendorRepositoryProvider)
          .submitSpecialDeliveryRequest(
            ordersCode: widget.ordersCode,
            customerName: _nameController.text.trim(),
            customerPhone: GhanaPhone.normalize(_phoneController.text.trim())!,
            dropoffAddress: _addressController.text.trim(),
            dropoffLat: _lat,
            dropoffLng: _lng,
            packageDescription: _packageController.text.trim().isEmpty
                ? null
                : _packageController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
          );
      if (mounted) setState(() => _isSent = true);
    } catch (e) {
      setState(
        () => _errorMessage = 'Could not send this request. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isSent) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 48),
            const SizedBox(height: 12),
            const Text(
              'Sent to dispatch',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 6),
            Text(
              "They'll price this and get a rider moving shortly - no need "
              'to fill in anything else.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Request a special delivery',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'For a job that needs its own price - dispatch reviews and '
                'prices this by hand rather than the usual per-km rate.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: "Customer's name"),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: "Customer's phone",
                ),
                validator: GhanaPhone.validator(),
              ),
              const SizedBox(height: 12),
              LocationField(
                controller: _addressController,
                label: 'Delivery address',
                mapTitle: 'Where should it be delivered?',
                hasLocation: _lat != null && _lng != null,
                confirmedHint: 'Location set',
                onPicked: (lat, lng) => setState(() {
                  _lat = lat;
                  _lng = lng;
                }),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _packageController,
                decoration: const InputDecoration(
                  labelText: 'What are we delivering? (optional)',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: "What makes this special? (optional)",
                  helperText: 'Anything dispatch should know before pricing '
                      'it - size, fragility, timing...',
                  helperMaxLines: 2,
                ),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: AppTheme.danger),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Send to dispatch'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
