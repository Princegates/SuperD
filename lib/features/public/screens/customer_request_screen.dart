import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/vendor.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/widgets/async_value_view.dart';
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
  final _addressController = TextEditingController();
  final _packageController = TextEditingController();

  double? _lat;
  double? _lng;
  bool _isGeocoding = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  DeliveryQuote? _quote;
  PriceEstimate? _estimate;

  @override
  void initState() {
    super.initState();
    // A base-fare-only estimate shows immediately, even before a location
    // is set - refreshed with a real distance-based range the moment one
    // is.
    _refreshEstimate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
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
          );
      if (mounted) setState(() => _estimate = estimate);
    } catch (_) {
      // An estimate is a nice-to-have, not required to submit - silently
      // skip it rather than blocking or alarming the customer over it.
    }
  }

  Future<void> _pickLocation() async {
    final initial = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : null;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: 'Where should it be delivered?',
          initialCenter: initial,
        ),
      ),
    );
    if (picked == null) return;

    setState(() {
      _lat = picked.latitude;
      _lng = picked.longitude;
      _isGeocoding = true;
    });
    unawaited(_refreshEstimate());
    final address = await reverseGeocode(picked.latitude, picked.longitude);
    if (mounted) {
      setState(() {
        _addressController.text =
            address ??
            '${picked.latitude.toStringAsFixed(5)}, '
                '${picked.longitude.toStringAsFixed(5)}';
        _isGeocoding = false;
      });
    }
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
            customerPhone: _phoneController.text.trim(),
            dropoffAddress: _addressController.text.trim(),
            dropoffLat: _lat,
            dropoffLng: _lng,
            packageDescription: _packageController.text.trim().isEmpty
                ? null
                : _packageController.text.trim(),
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
      return _SubmittedCard(code: widget.code, quote: _quote!);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ordering from ${widget.vendor.vendorName}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(height: 4),
            const Text(
              "Fill in your details and we'll get a rider assigned to you.",
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Your name'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone number'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _addressController,
              decoration: const InputDecoration(labelText: 'Delivery address'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _isGeocoding ? null : _pickLocation,
                icon: _isGeocoding
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.map_outlined, size: 18),
                label: const Text('Or pin it on the map'),
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _packageController,
              decoration: const InputDecoration(
                labelText: 'What are we delivering? (optional)',
              ),
            ),
            if (_estimate case final estimate?) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.payments_outlined,
                      size: 18,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        estimate.low == estimate.high
                            ? 'Estimated price: ${estimate.currency} '
                                  '${estimate.high.toStringAsFixed(2)}'
                            : 'Estimated price: ${estimate.currency} '
                                  '${estimate.low.toStringAsFixed(2)}–'
                                  '${estimate.high.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: const TextStyle(color: AppTheme.danger),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 20),
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
                  : const Text('Request delivery'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SubmittedCard extends StatelessWidget {
  const _SubmittedCard({required this.code, required this.quote});

  final String code;
  final DeliveryQuote quote;

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
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => context.go('/v/$code/orders'),
            child: const Text('Track this order'),
          ),
        ],
      ),
    );
  }
}
