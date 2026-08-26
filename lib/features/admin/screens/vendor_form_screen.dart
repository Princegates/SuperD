import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/utils/vendor_link.dart';
import '../providers/admin_providers.dart';

/// Dispatcher/super-admin "Add vendor" form - the admin-side counterpart to
/// the public self-signup page, for businesses that get registered on their
/// behalf. Same `register_vendor` call under the hood, just with
/// `createdBy` set to whoever's filling it in.
class VendorFormScreen extends ConsumerStatefulWidget {
  const VendorFormScreen({super.key});

  @override
  ConsumerState<VendorFormScreen> createState() => _VendorFormScreenState();
}

class _VendorFormScreenState extends ConsumerState<VendorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _locationController = TextEditingController();

  String? _zoneId;
  double? _lat;
  double? _lng;
  bool _isGeocoding = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _resultCode;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final initial = (_lat != null && _lng != null)
        ? LatLng(_lat!, _lng!)
        : null;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: "Vendor's location",
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
      setState(() => _errorMessage = "Please set the vendor's map location.");
      return;
    }

    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final code = await ref
          .read(vendorRepositoryProvider)
          .registerVendor(
            vendorName: _nameController.text.trim(),
            locationLat: _lat!,
            locationLng: _lng!,
            phone: _phoneController.text.trim(),
            zoneId: _zoneId,
            createdBy: userId,
          );
      ref.invalidate(vendorsProvider);
      if (mounted) setState(() => _resultCode = code);
    } catch (e) {
      setState(
        () =>
            _errorMessage = 'Could not register this vendor. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(zonesProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('Add vendor')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _resultCode != null
              ? _VendorCreatedCard(code: _resultCode!)
              : Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Vendor name',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Telephone number',
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? 'Required' : null,
                      ),
                      const SizedBox(height: 14),
                      DropdownButtonFormField<String?>(
                        initialValue: _zoneId,
                        decoration: const InputDecoration(
                          labelText: 'Zone / area',
                        ),
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
                        onChanged: (value) => setState(() => _zoneId = value),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _locationController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Exact location',
                          helperText: 'Tap below to pin it on the map',
                        ),
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
                            : const Text('Add vendor'),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _VendorCreatedCard extends StatelessWidget {
  const _VendorCreatedCard({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final link = vendorLink(code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.check_circle, color: AppTheme.success, size: 56),
        const SizedBox(height: 12),
        const Text(
          'Vendor registered',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 6),
        const Text(
          'Share this link with the vendor - their customers use it to '
          'request deliveries, and it also shows the vendor their own orders.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        Card(
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
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton(
          onPressed: () => context.pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
