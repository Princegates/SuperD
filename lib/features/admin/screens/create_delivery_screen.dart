import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/payment_method.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/utils/geocode_search.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/widgets/address_autocomplete_field.dart';
import '../../../shared/widgets/schedule_picker.dart';
import '../providers/admin_providers.dart';

class CreateDeliveryScreen extends ConsumerStatefulWidget {
  const CreateDeliveryScreen({super.key});

  @override
  ConsumerState<CreateDeliveryScreen> createState() =>
      _CreateDeliveryScreenState();
}

class _CreateDeliveryScreenState extends ConsumerState<CreateDeliveryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _customerEmailController = TextEditingController();
  final _pickupController = TextEditingController();
  final _dropoffController = TextEditingController();
  final _packageController = TextEditingController();
  final _notesController = TextEditingController();
  final _feeController = TextEditingController();

  double? _pickupLat;
  double? _pickupLng;
  double? _dropoffLat;
  double? _dropoffLng;

  String? _assignedDriverId;
  String? _vehicleTypeId;
  DateTime? _scheduledAt;
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _isSubmitting = false;
  bool _isLocating = false;
  bool _isGeocodingPickup = false;
  bool _isGeocodingDropoff = false;
  String? _errorMessage;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _customerEmailController.dispose();
    _pickupController.dispose();
    _dropoffController.dispose();
    _packageController.dispose();
    _notesController.dispose();
    _feeController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocationForPickup() async {
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Location permission denied');
      }

      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _pickupLat = point.latitude;
        _pickupLng = point.longitude;
      });

      final address = await reverseGeocode(point.latitude, point.longitude);
      if (mounted) {
        setState(() => _pickupController.text = address ?? _coordsLabel(point));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pickCustomerLocation() async {
    final initial = (_dropoffLat != null && _dropoffLng != null)
        ? LatLng(_dropoffLat!, _dropoffLng!)
        : null;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: "Customer's location",
          initialCenter: initial,
        ),
      ),
    );
    if (picked == null) return;

    setState(() {
      _dropoffLat = picked.latitude;
      _dropoffLng = picked.longitude;
      _isGeocodingDropoff = true;
    });

    final address = await reverseGeocode(picked.latitude, picked.longitude);
    if (mounted) {
      setState(() {
        _dropoffController.text = address ?? _coordsLabel(picked);
        _isGeocodingDropoff = false;
      });
    }
  }

  Future<void> _pickPickupLocation() async {
    final initial = (_pickupLat != null && _pickupLng != null)
        ? LatLng(_pickupLat!, _pickupLng!)
        : null;
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: 'Pickup location',
          initialCenter: initial,
        ),
      ),
    );
    if (picked == null) return;

    setState(() {
      _pickupLat = picked.latitude;
      _pickupLng = picked.longitude;
      _isGeocodingPickup = true;
    });

    final address = await reverseGeocode(picked.latitude, picked.longitude);
    if (mounted) {
      setState(() {
        _pickupController.text = address ?? _coordsLabel(picked);
        _isGeocodingPickup = false;
      });
    }
  }

  String _coordsLabel(LatLng point) =>
      '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';

  void _selectPickupSuggestion(GeocodeResult result) {
    setState(() {
      _pickupLat = result.location.latitude;
      _pickupLng = result.location.longitude;
    });
  }

  void _selectDropoffSuggestion(GeocodeResult result) {
    setState(() {
      _dropoffLat = result.location.latitude;
      _dropoffLng = result.location.longitude;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final deliveryId = await ref
          .read(deliveryRepositoryProvider)
          .createDelivery(
            customerName: _customerNameController.text.trim(),
            customerPhone: _customerPhoneController.text.trim(),
            customerEmail: _customerEmailController.text.trim(),
            pickupAddress: _pickupController.text.trim(),
            pickupLat: _pickupLat,
            pickupLng: _pickupLng,
            dropoffAddress: _dropoffController.text.trim(),
            dropoffLat: _dropoffLat,
            dropoffLng: _dropoffLng,
            packageDescription: _packageController.text.trim().isEmpty
                ? null
                : _packageController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            createdBy: userId,
            assignedDriverId: _assignedDriverId,
            scheduledAt: _scheduledAt,
            vehicleTypeId: _vehicleTypeId,
          );

      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'delivery_created',
        entityType: 'delivery',
        entityId: deliveryId,
        summary: 'Created delivery for ${_customerNameController.text.trim()}',
      );

      final fee = double.tryParse(_feeController.text.trim());
      if (fee != null && fee > 0) {
        final currency =
            ref.read(appSettingsProvider).valueOrNull?.currency ?? 'GHS';
        await ref
            .read(paymentRepositoryProvider)
            .recordPayment(
              deliveryId: deliveryId,
              amount: fee,
              method: _paymentMethod,
              currency: currency,
            );
      }

      if (mounted) context.pop();
    } on PostgrestException catch (e) {
      // The pre-assigned driver may be at the cap on active deliveries -
      // see enforce_delivery_insert() in 0048_manual_assignment_cap.sql -
      // surface that reason rather than a generic failure.
      setState(() => _errorMessage = e.message);
    } catch (e) {
      setState(
        () => _errorMessage = 'Could not create delivery. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final drivers = ref.watch(
      rankedDriversProvider((pickupLat: _pickupLat, pickupLng: _pickupLng)),
    );
    final currency =
        ref.watch(appSettingsProvider).valueOrNull?.currency ?? 'GHS';
    final vehicleTypes =
        ref.watch(vehicleTypesProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('New delivery')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _SectionLabel('Customer'),
                TextFormField(
                  controller: _customerNameController,
                  decoration: const InputDecoration(labelText: 'Customer name'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customerPhoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Customer phone',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _customerEmailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Customer email',
                    helperText:
                        'Lets repeat orders notify by email instead of SMS',
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Enter a valid email'
                      : null,
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Pickup'),
                AddressAutocompleteField(
                  controller: _pickupController,
                  decoration: const InputDecoration(
                    labelText: 'Pickup address',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  onPlaceSelected: _selectPickupSuggestion,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isLocating
                        ? null
                        : _useCurrentLocationForPickup,
                    icon: _isLocating
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location, size: 18),
                    label: Text(
                      _pickupLat != null
                          ? 'Pickup location captured'
                          : 'Use current location for pickup',
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isGeocodingPickup ? null : _pickPickupLocation,
                    icon: _isGeocodingPickup
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.map_outlined, size: 18),
                    label: const Text('Or set pickup location on map'),
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionLabel('Drop-off'),
                AddressAutocompleteField(
                  controller: _dropoffController,
                  decoration: const InputDecoration(
                    labelText: 'Drop-off address',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                  onPlaceSelected: _selectDropoffSuggestion,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _isGeocodingDropoff
                        ? null
                        : _pickCustomerLocation,
                    icon: _isGeocodingDropoff
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.map_outlined, size: 18),
                    label: const Text("Set customer's location on map"),
                  ),
                ),
                const SizedBox(height: 12),
                const _SectionLabel('Package'),
                TextFormField(
                  controller: _packageController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Vehicle'),
                DropdownButtonFormField<String?>(
                  initialValue: _vehicleTypeId,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle needed (optional)',
                  ),
                  hint: const Text('Any vehicle'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Any vehicle'),
                    ),
                    for (final type in vehicleTypes)
                      DropdownMenuItem<String?>(
                        value: type.id,
                        child: Text(type.name),
                      ),
                  ],
                  onChanged: (value) => setState(() => _vehicleTypeId = value),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('When'),
                SchedulePicker(
                  value: _scheduledAt,
                  onChanged: (value) => setState(() => _scheduledAt = value),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Payment'),
                TextFormField(
                  controller: _feeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Delivery fee ($currency, optional)',
                    prefixIcon: const Icon(Icons.attach_money),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    return double.tryParse(v.trim()) == null
                        ? 'Enter a valid amount'
                        : null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<PaymentMethod>(
                  initialValue: _paymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment method',
                  ),
                  items: [
                    for (final method in PaymentMethod.values)
                      DropdownMenuItem(
                        value: method,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(method.icon, size: 16),
                            const SizedBox(width: 8),
                            Text(method.label),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value!),
                ),
                if (_paymentMethod == PaymentMethod.mobileMoney) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Recorded as pending until confirmed - the same as any '
                    'other method. Once the customer sends Mobile Money for '
                    'this delivery, mark the payment paid from the delivery '
                    'detail screen.',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 20),
                const _SectionLabel('Assign driver'),
                DropdownButtonFormField<String?>(
                  initialValue: _assignedDriverId,
                  decoration: const InputDecoration(
                    labelText: 'Driver (optional)',
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Leave unassigned'),
                    ),
                    for (final driver in drivers)
                      DropdownMenuItem<String?>(
                        value: driver.id,
                        child: Text(driver.displayName),
                      ),
                  ],
                  onChanged: (value) =>
                      setState(() => _assignedDriverId = value),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: AppTheme.danger),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 28),
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
                      : const Text('Create delivery'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
