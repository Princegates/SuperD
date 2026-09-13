import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/env.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/vehicle_type.dart';
import '../../../models/vendor.dart';
import '../../../shared/utils/ghana_phone.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/location_field.dart';
import '../../../shared/widgets/schedule_picker.dart';
import '../../../shared/widgets/turnstile_widget.dart';
import '../providers/public_providers.dart';

/// The page a customer lands on after opening a vendor's link. No login -
/// they just say who they are and where the package should go; pickup is
/// always the vendor's own registered location.
class CustomerRequestScreen extends ConsumerWidget {
  const CustomerRequestScreen({super.key, required this.code});

  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorState = ref.watch(vendorByCodeProvider(code));

    return Scaffold(
      appBar: AppBar(title: const Text('Request a delivery')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: AsyncValueView<VendorPublicInfo?>(
              value: vendorState,
              data: (vendor) {
                if (vendor == null || !vendor.isActive) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "This link isn't valid or is no longer active. "
                      'Please check with the business for an up-to-date link.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return _RequestForm(code: code, vendor: vendor);
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestForm extends ConsumerStatefulWidget {
  const _RequestForm({required this.code, required this.vendor});

  final String code;
  final VendorPublicInfo vendor;

  @override
  ConsumerState<_RequestForm> createState() => _RequestFormState();
}

class _RequestFormState extends ConsumerState<_RequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _packageController = TextEditingController();

  double? _lat;
  double? _lng;
  bool _isSubmitting = false;
  String? _errorMessage;
  DeliveryQuote? _quote;
  PriceEstimate? _estimate;
  DateTime? _scheduledAt;

  /// Set once the visitor passes the Cloudflare Turnstile challenge - see
  /// `TurnstileWidget` and the README's "Public form protection" section.
  /// Stays null forever on a project that hasn't set TURNSTILE_SITE_KEY
  /// (the widget renders nothing in that case) - [_canSubmit] accounts
  /// for that, only requiring a token once one's actually expected.
  String? _turnstileToken;

  bool get _canSubmit =>
      !_isSubmitting &&
      (Env.turnstileSiteKey.isEmpty || _turnstileToken != null);

  /// Null until either the customer picks one, or [publicVehicleTypesProvider]
  /// loads and the default (motorcycle, out of the box) is applied - see the
  /// `ref.listen` in [build].
  String? _vehicleTypeId;

  /// The real road distance to [_lat]/[_lng] from the vendor's location,
  /// fetched via Google Directions (see [_refreshRoadDistance]) - null
  /// until that finishes (or if it fails), in which case pricing just
  /// falls back to straight-line distance, computed server-side.
  double? _roadDistanceKm;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _packageController.dispose();
    super.dispose();
  }

  Future<void> _refreshEstimate() async {
    try {
      final estimate = await ref
          .read(vendorRepositoryProvider)
          .fetchPriceEstimate(
            code: widget.code,
            dropoffLat: _lat,
            dropoffLng: _lng,
            roadDistanceKm: _roadDistanceKm,
            vehicleTypeId: _vehicleTypeId,
          );
      if (mounted) setState(() => _estimate = estimate);
    } catch (_) {
      // An estimate is a nice-to-have, not required to submit - silently
      // skip it rather than blocking or alarming the customer over it.
    }
  }

  /// Fetches the real road distance from the vendor to [_lat]/[_lng] (via
  /// Google Directions, see `VendorRepository.fetchRoadDistanceKm`), then
  /// refreshes the price estimate with it. Silently does nothing if
  /// either the vendor or the drop-off has no coordinates - pricing just
  /// uses the server's straight-line fallback in that case.
  Future<void> _refreshPricing() async {
    final vendorLat = widget.vendor.locationLat;
    final vendorLng = widget.vendor.locationLng;
    if (_lat != null &&
        _lng != null &&
        vendorLat != null &&
        vendorLng != null) {
      final distanceKm = await ref
          .read(vendorRepositoryProvider)
          .fetchRoadDistanceKm(
            originLat: vendorLat,
            originLng: vendorLng,
            destLat: _lat!,
            destLng: _lng!,
          );
      if (mounted) setState(() => _roadDistanceKm = distanceKm);
    }
    await _refreshEstimate();
  }

  /// Any of [LocationField]'s three routes to a coordinate lands here -
  /// typed suggestion, the device's own position, or a pin on the map.
  void _onLocationPicked(double lat, double lng) {
    setState(() {
      _lat = lat;
      _lng = lng;
      _roadDistanceKm = null;
    });
    unawaited(_refreshPricing());
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final quote = await ref
          .read(vendorRepositoryProvider)
          .submitDeliveryRequest(
            code: widget.code,
            customerName: _nameController.text.trim(),
            customerPhone: GhanaPhone.normalize(_phoneController.text.trim())!,
            dropoffAddress: _addressController.text.trim(),
            dropoffLat: _lat,
            dropoffLng: _lng,
            packageDescription: _packageController.text.trim().isEmpty
                ? null
                : _packageController.text.trim(),
            roadDistanceKm: _roadDistanceKm,
            scheduledAt: _scheduledAt,
            customerEmail: _emailController.text.trim(),
            vehicleTypeId: _vehicleTypeId,
            turnstileToken: _turnstileToken,
          );
      if (mounted) setState(() => _quote = quote);
    } catch (e) {
      setState(
        () =>
            _errorMessage = 'Could not submit your request. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_quote != null) {
      return _SubmittedCard(quote: _quote!, scheduledAt: _scheduledAt);
    }

    final vehicleTypes =
        ref.watch(publicVehicleTypesProvider).valueOrNull ?? const [];
    // Applies the default vehicle type (motorcycle, out of the box) the
    // moment the list loads - only once, and only if the customer hasn't
    // already picked one themselves.
    ref.listen<AsyncValue<List<VehicleType>>>(publicVehicleTypesProvider, (
      previous,
      next,
    ) {
      final types = next.valueOrNull;
      if (types == null || types.isEmpty || _vehicleTypeId != null) return;
      final defaultType = types.firstWhere(
        (t) => t.isDefault,
        orElse: () => types.first,
      );
      setState(() => _vehicleTypeId = defaultType.id);
      unawaited(_refreshEstimate());
    });

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VendorHeader(vendorName: widget.vendor.vendorName),
            const SizedBox(height: 20),
            _FormStep(
              step: 1,
              title: 'Who should the rider call?',
              children: [
                TextFormField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number',
                    prefixIcon: Icon(Icons.call_outlined, size: 20),
                    helperText: 'The rider calls this when they arrive',
                  ),
                  validator: GhanaPhone.validator(),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline, size: 20),
                    helperText: 'Where your tracking link goes',
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormStep(
              step: 2,
              title: 'Where are we taking it?',
              children: [
                LocationField(
                  controller: _addressController,
                  label: 'Delivery address',
                  mapTitle: 'Where should it be delivered?',
                  helperText: "Can't name the street? Drop a pin instead",
                  hasLocation: _lat != null && _lng != null,
                  confirmedHint: 'Got it - your price is below',
                  initialCenter: (_lat != null && _lng != null)
                      ? LatLng(_lat!, _lng!)
                      : null,
                  onPicked: _onLocationPicked,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ],
            ),
            const SizedBox(height: 14),
            _FormStep(
              step: 3,
              title: 'What and when?',
              children: [
                TextFormField(
                  controller: _packageController,
                  decoration: const InputDecoration(
                    labelText: 'What are we delivering?',
                    prefixIcon: Icon(Icons.inventory_2_outlined, size: 20),
                    helperText: 'Optional - helps the rider bring the right bag',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _vehicleTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle',
                    prefixIcon: Icon(Icons.two_wheeler_outlined, size: 20),
                    isDense: true,
                  ),
                  hint: const Text('Loading...'),
                  items: [
                    for (final type in vehicleTypes)
                      DropdownMenuItem(value: type.id, child: Text(type.name)),
                  ],
                  onChanged: vehicleTypes.isEmpty
                      ? null
                      : (value) {
                          setState(() => _vehicleTypeId = value);
                          unawaited(_refreshEstimate());
                        },
                ),
                const SizedBox(height: 16),
                SchedulePicker(
                  value: _scheduledAt,
                  onChanged: (value) => setState(() => _scheduledAt = value),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _PriceCard(
              estimate: _estimate,
              hasLocation: _lat != null && _lng != null,
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
            Center(
              child: TurnstileWidget(
                onToken: (token) => setState(() => _turnstileToken = token),
              ),
            ),
            const SizedBox(height: 4),
            ElevatedButton(
              onPressed: _canSubmit ? _submit : null,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Request delivery'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Who the customer is ordering from, said once and warmly. This page is
/// often the first time someone has seen SuperD at all - they followed a
/// link from a shop - so it opens by confirming they're in the right place
/// rather than with a bare form.
class _VendorHeader extends StatelessWidget {
  const _VendorHeader({required this.vendorName});

  final String vendorName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primary.withValues(alpha: 0.12),
            AppTheme.primary.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.storefront_outlined,
              size: 20,
              color: AppTheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  vendorName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Three quick steps and a rider is on the way.',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One numbered stage of the form. Three short steps read as less work
/// than the same nine fields in one unbroken column, and the numbers give
/// someone on a phone a sense of how much is left.
class _FormStep extends StatelessWidget {
  const _FormStep({
    required this.step,
    required this.title,
    required this.children,
  });

  final int step;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                height: 22,
                width: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$step',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

/// The price, which is the thing a customer actually wants to know and the
/// reason the location question is worth answering properly. Shown as a
/// real figure once there's a coordinate, and as a plain nudge before
/// then - not an error, just the missing half of the trade.
class _PriceCard extends StatelessWidget {
  const _PriceCard({required this.estimate, required this.hasLocation});

  final PriceEstimate? estimate;
  final bool hasLocation;

  @override
  Widget build(BuildContext context) {
    final showPrice = hasLocation && estimate != null;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: showPrice
            ? AppTheme.primary.withValues(alpha: 0.08)
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: showPrice
              ? AppTheme.primary.withValues(alpha: 0.35)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Icon(
            showPrice ? Icons.payments_outlined : Icons.location_searching,
            size: 20,
            color: showPrice ? AppTheme.primary : Colors.grey.shade600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: showPrice
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your delivery',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        estimate!.low == estimate!.high
                            ? '${estimate!.currency} '
                                  '${estimate!.high.toStringAsFixed(2)}'
                            : '${estimate!.currency} '
                                  '${estimate!.low.toStringAsFixed(2)} - '
                                  '${estimate!.high.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          color: AppTheme.primary,
                        ),
                      ),
                    ],
                  )
                : Text(
                    'Set your delivery address above to see the price.',
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12.5,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({required this.quote, this.scheduledAt});

  final DeliveryQuote quote;
  final DateTime? scheduledAt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.check_circle, color: AppTheme.success, size: 56),
          const SizedBox(height: 12),
          const Text(
            'Request received!',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
          ),
          const SizedBox(height: 6),
          Text(
            "We'll assign a rider shortly. Your tracking code is "
            '#${quote.trackingCode}.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.black54),
          ),
          if (quote.amount > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Delivery fee: ${quote.currency} '
              '${quote.amount.toStringAsFixed(2)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (scheduledAt case final scheduled?) ...[
            const SizedBox(height: 6),
            Text(
              'Scheduled for '
              '${DateFormat('EEE d MMM, h:mm a').format(scheduled)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/t/${quote.trackingCode}'),
            child: const Text('Track this order'),
          ),
        ],
      ),
    );
  }
}
