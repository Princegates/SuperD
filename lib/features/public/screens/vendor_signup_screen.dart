import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/vendor.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/geocode_search.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/utils/vendor_link.dart';
import '../../../shared/widgets/address_autocomplete_field.dart';
import '../../admin/providers/admin_providers.dart';

/// Public, no-login page where a business registers itself as a vendor and
/// gets back a unique link to share with its own customers. Reachable at
/// `/vendor` from anywhere - no SuperD account needed.
class VendorSignupScreen extends ConsumerStatefulWidget {
  const VendorSignupScreen({super.key});

  @override
  ConsumerState<VendorSignupScreen> createState() => _VendorSignupScreenState();
}

class _VendorSignupScreenState extends ConsumerState<VendorSignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _locationController = TextEditingController();

  String? _zoneId;
  double? _lat;
  double? _lng;
  bool _isGeocoding = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  VendorRegistration? _registration;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  /// The vendor picked one of the as-you-type suggestions instead of using
  /// the map - same effect as [_pickLocation] once a point is chosen, just
  /// skipping the map screen and reverse-geocode step since the
  /// suggestion already carries both.
  void _selectSuggestion(GeocodeResult result) {
    setState(() {
      _lat = result.location.latitude;
      _lng = result.location.longitude;
    });
  }

  Future<void> _pickLocation() async {
    final initial = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : null;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: 'Your business location',
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
    final address = await reverseGeocode(picked.latitude, picked.longitude);
    if (mounted) {
      setState(() {
        _locationController.text =
            address ??
            '${picked.latitude.toStringAsFixed(5)}, '
                '${picked.longitude.toStringAsFixed(5)}';
        _isGeocoding = false;
      });
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_lat == null || _lng == null) {
      setState(() => _errorMessage = 'Please set your location on the map.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final registration = await ref
          .read(vendorRepositoryProvider)
          .registerVendor(
            vendorName: _nameController.text.trim(),
            locationLat: _lat!,
            locationLng: _lng!,
            phone: _phoneController.text.trim(),
            email: _emailController.text.trim(),
            zoneId: _zoneId,
          );
      if (mounted) setState(() => _registration = registration);
    } catch (e) {
      setState(() => _errorMessage = 'Could not register. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(zonesProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Register your business')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: _registration != null
                  ? _SuccessCard(registration: _registration!)
                  : Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            "Get a link to share with your customers - they'll "
                            "use it to request a delivery, and a rider gets "
                            'assigned automatically.',
                            style: TextStyle(color: Colors.black54),
                          ),
                          const SizedBox(height: 24),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(
                              labelText: 'Business / vendor name',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Telephone number',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              helperText: "We'll send your link here",
                            ),
                            validator: (v) => (v == null || !v.contains('@'))
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String?>(
                            initialValue: _zoneId,
                            decoration: const InputDecoration(
                              labelText: 'Zone / area (optional)',
                            ),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('Not sure'),
                              ),
                              for (final zone in zones)
                                DropdownMenuItem<String?>(
                                  value: zone.id,
                                  child: Text(zone.name),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _zoneId = value),
                          ),
                          const SizedBox(height: 14),
                          AddressAutocompleteField(
                            controller: _locationController,
                            decoration: const InputDecoration(
                              labelText: 'Exact location',
                              helperText:
                                  'Start typing, or pin it on the map below',
                            ),
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Required'
                                : null,
                            onPlaceSelected: _selectSuggestion,
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.map_outlined, size: 18),
                              label: const Text('Set location on map'),
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
                                : const Text('Get my link'),
                          ),
                        ],
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SuccessCard extends StatelessWidget {
  const _SuccessCard({required this.registration});

  final VendorRegistration registration;

  @override
  Widget build(BuildContext context) {
    final link = vendorLink(registration.code);
    final ordersLink = vendorOrdersLink(registration.ordersCode);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: AppTheme.success, size: 56),
        const SizedBox(height: 12),
        const Text(
          "You're all set!",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 6),
        const Text(
          'Share this link with your customers so they can request a '
          'delivery.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        _LinkCard(link: link),
        const SizedBox(height: 24),
        const Text(
          'This second link is private - it shows every order ever placed '
          "through your link above, so it's only for you. Never share it "
          'with a customer.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 12),
        _LinkCard(link: ordersLink),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () =>
              context.go('/vendor-orders/${registration.ordersCode}'),
          child: const Text('View my orders'),
        ),
      ],
    );
  }
}

class _LinkCard extends StatelessWidget {
  const _LinkCard({required this.link});

  final String link;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: SelectableText(
                link,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: link));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Link copied')));
              },
            ),
          ],
        ),
      ),
    );
  }
}
