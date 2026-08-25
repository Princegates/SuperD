import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/payment_method.dart';
import '../../../shared/screens/location_picker_screen.dart';
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
  PaymentMethod _paymentMethod = PaymentMethod.cash;
  bool _isSubmitting = false;
  bool _isLocating = false;
  String? _errorMessage;

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerPhoneController.dispose();
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
      setState(() {
        _pickupLat = position.latitude;
        _pickupLng = position.longitude;
        if (_pickupController.text.trim().isEmpty) {
          _pickupController.text =
              '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        }
      });
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
    if (picked != null) {
      setState(() {
        _dropoffLat = picked.latitude;
        _dropoffLng = picked.longitude;
      });
    }
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
            customerPhone: _customerPhoneController.text.trim().isEmpty
                ? null
                : _customerPhoneController.text.trim(),
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
          );

      final fee = double.tryParse(_feeController.text.trim());
      if (fee != null && fee > 0) {
        await ref
            .read(paymentRepositoryProvider)
            .recordPayment(
              deliveryId: deliveryId,
              amount: fee,
              method: _paymentMethod,
            );
      }

      if (mounted) context.pop();
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
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];

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
                    labelText: 'Customer phone (optional)',
                  ),
                ),
                const SizedBox(height: 20),
                const _SectionLabel('Pickup'),
                TextFormField(
                  controller: _pickupController,
                  decoration: const InputDecoration(
                    labelText: 'Pickup address',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
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
                const SizedBox(height: 12),
                const _SectionLabel('Drop-off'),
                TextFormField(
                  controller: _dropoffController,
                  decoration: const InputDecoration(
                    labelText: 'Drop-off address',
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _pickCustomerLocation,
                    icon: const Icon(Icons.map_outlined, size: 18),
                    label: Text(
                      _dropoffLat != null
                          ? 'Customer location set'
                          : "Set customer's location on map",
                    ),
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
                const _SectionLabel('Payment'),
                TextFormField(
                  controller: _feeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Delivery fee (optional)',
                    prefixIcon: Icon(Icons.attach_money),
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
                        child: Text(method.label),
                      ),
                  ],
                  onChanged: (value) => setState(() => _paymentMethod = value!),
                ),
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
