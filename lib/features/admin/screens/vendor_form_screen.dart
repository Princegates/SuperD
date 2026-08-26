import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/vendor.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/utils/vendor_link.dart';
import '../providers/admin_providers.dart';

/// Dispatcher/super-admin "Add vendor" form when [existing] is null - the
/// admin-side counterpart to the public self-signup page, for businesses
/// that get registered on their behalf. Same `register_vendor` call under
/// the hood, just with `createdBy` set to whoever's filling it in.
///
/// When [existing] is set, this becomes the edit form instead: name,
/// phone, zone, and location can all be changed, and the vendor's link can
/// be deactivated/reactivated - editing never changes the `code` itself,
/// since that's the link already shared with the vendor's customers.
class VendorFormScreen extends ConsumerStatefulWidget {
  const VendorFormScreen({super.key, this.existing});

  final Vendor? existing;

  bool get isEditing => existing != null;

  @override
  ConsumerState<VendorFormScreen> createState() => _VendorFormScreenState();
}

class _VendorFormScreenState extends ConsumerState<VendorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.vendorName,
  );
  late final _phoneController = TextEditingController(
    text: widget.existing?.phone,
  );
  late final _locationController = TextEditingController(
    text: _initialLocationLabel(),
  );

  late String? _zoneId = widget.existing?.zoneId;
  late double? _lat = widget.existing?.locationLat;
  late double? _lng = widget.existing?.locationLng;
  late bool _isActive = widget.existing?.isActive ?? true;
  bool _isGeocoding = false;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _resultCode;

  String? _initialLocationLabel() {
    final vendor = widget.existing;
    if (vendor?.locationLat == null || vendor?.locationLng == null) {
      return null;
    }
    return '${vendor!.locationLat!.toStringAsFixed(5)}, '
        '${vendor.locationLng!.toStringAsFixed(5)}';
  }

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

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final repo = ref.read(vendorRepositoryProvider);
      if (widget.isEditing) {
        final vendor = widget.existing!;
        await repo.updateVendor(
          id: vendor.id,
          vendorName: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          zoneId: _zoneId,
          locationLat: _lat,
          locationLng: _lng,
        );
        if (_isActive != vendor.isActive) {
          await repo.setVendorActive(vendor.id, _isActive);
        }
        ref.invalidate(vendorsProvider);
        if (mounted) context.pop();
      } else {
        final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
        final code = await repo.registerVendor(
          vendorName: _nameController.text.trim(),
          locationLat: _lat!,
          locationLng: _lng!,
          phone: _phoneController.text.trim(),
          zoneId: _zoneId,
          createdBy: userId,
        );
        ref.invalidate(vendorsProvider);
        if (mounted) setState(() => _resultCode = code);
      }
    } catch (e) {
      setState(
        () => _errorMessage = widget.isEditing
            ? 'Could not save changes. Please try again.'
            : 'Could not register this vendor. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final zones = ref.watch(zonesProvider).valueOrNull ?? [];

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEditing ? 'Edit vendor' : 'Add vendor'),
      ),
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
                      if (widget.isEditing) ...[
                        const SizedBox(height: 14),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Link active'),
                          subtitle: Text(
                            _isActive
                                ? "Customers can request deliveries from this vendor's link"
                                : "This vendor's link no longer accepts new requests",
                          ),
                          value: _isActive,
                          onChanged: (value) =>
                              setState(() => _isActive = value),
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
                            : Text(
                                widget.isEditing
                                    ? 'Save changes'
                                    : 'Add vendor',
                              ),
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
