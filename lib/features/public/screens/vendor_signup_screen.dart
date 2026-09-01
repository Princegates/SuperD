import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/config/env.dart';
import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/repositories/vendor_repository.dart'
    show VendorSubscriptionException;
import '../../../models/vendor.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/geocode_search.dart';
import '../../../shared/utils/ghana_phone.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/utils/vendor_link.dart';
import '../../../shared/widgets/address_autocomplete_field.dart';
import '../../../shared/widgets/turnstile_widget.dart';
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

  /// Set once the visitor passes the Cloudflare Turnstile challenge - see
  /// `TurnstileWidget` and the README's "Public form protection" section.
  /// Stays null forever on a project that hasn't set TURNSTILE_SITE_KEY
  /// (the widget renders nothing in that case) - [_canSubmit] accounts
  /// for that, only requiring a token once one's actually expected.
  String? _turnstileToken;

  bool get _canSubmit =>
      !_isSubmitting &&
      (Env.turnstileSiteKey.isEmpty || _turnstileToken != null);

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
          .registerVendorPublic(
            vendorName: _nameController.text.trim(),
            locationLat: _lat!,
            locationLng: _lng!,
            phone: GhanaPhone.normalize(_phoneController.text.trim())!,
            email: _emailController.text.trim(),
            zoneId: _zoneId,
            turnstileToken: _turnstileToken,
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
              child: _registration == null
                  ? Form(
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
                            validator: GhanaPhone.validator(),
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
                          const SizedBox(height: 16),
                          Center(
                            child: TurnstileWidget(
                              onToken: (token) =>
                                  setState(() => _turnstileToken = token),
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
                                : const Text('Get my link'),
                          ),
                        ],
                      ),
                    )
                  : (_registration!.isActive
                        ? _SuccessCard(registration: _registration!)
                        : _SubscriptionPaymentCard(
                            registration: _registration!,
                          )),
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

const _networks = [
  (value: 'mtn-gh', label: 'MTN Mobile Money'),
  (value: 'vodafone-gh', label: 'Vodafone Cash'),
  (value: 'tigo-gh', label: 'AirtelTigo Money'),
];

/// Shown instead of [_SuccessCard] right after registering, when the
/// one-time subscription fee is on (`0074_vendor_subscriptions.sql`) -
/// the new vendor's link stays inactive until they pay it here, via the
/// same real-time Mobile Money flow a driver already uses for their
/// daily fee (see `DailyFeeBanner`). Polls [VendorRepository.fetchVendorByCode]
/// after a charge attempt to notice the moment Paystack's webhook
/// activates the link, then swaps itself for the usual success screen -
/// there's no session here to push a live update through instead.
class _SubscriptionPaymentCard extends ConsumerStatefulWidget {
  const _SubscriptionPaymentCard({required this.registration});

  final VendorRegistration registration;

  @override
  ConsumerState<_SubscriptionPaymentCard> createState() =>
      _SubscriptionPaymentCardState();
}

class _SubscriptionPaymentCardState
    extends ConsumerState<_SubscriptionPaymentCard> {
  final _phoneController = TextEditingController();
  String _network = _networks.first.value;
  bool _isCharging = false;
  bool _isPolling = false;
  Timer? _pollTimer;
  String? _message;
  String? _error;
  VendorPublicInfo? _status;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    final info = await ref
        .read(vendorRepositoryProvider)
        .fetchVendorByCode(widget.registration.code);
    if (mounted) setState(() => _status = info);
  }

  void _startPolling() {
    _pollTimer?.cancel();
    setState(() => _isPolling = true);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      final info = await ref
          .read(vendorRepositoryProvider)
          .fetchVendorByCode(widget.registration.code);
      if (!mounted) return;
      setState(() => _status = info);
      if (info?.isActive == true) {
        _pollTimer?.cancel();
        setState(() => _isPolling = false);
      }
    });
  }

  Future<void> _pay() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) {
      setState(() => _error = 'Enter a Mobile Money number.');
      return;
    }
    setState(() {
      _isCharging = true;
      _error = null;
      _message = null;
    });
    try {
      final message = await ref
          .read(vendorRepositoryProvider)
          .payVendorSubscription(
            code: widget.registration.code,
            phone: phone,
            network: _network,
          );
      if (mounted) {
        setState(() => _message = message);
        _startPolling();
      }
    } on VendorSubscriptionException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isCharging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_status?.isActive == true) {
      return _SuccessCard(registration: widget.registration);
    }

    final fee = _status?.subscriptionFeeAmount;
    final currency = _status?.currency ?? 'GHS';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.payments_outlined, color: AppTheme.primary, size: 56),
        const SizedBox(height: 12),
        const Text(
          "You're almost there",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        const SizedBox(height: 6),
        Text(
          fee == null
              ? 'Pay a one-time activation fee to start accepting orders.'
              : 'Pay a one-time activation fee of $currency '
                    '${fee.toStringAsFixed(2)} to start accepting orders.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Mobile Money number'),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _network,
          decoration: const InputDecoration(labelText: 'Network'),
          items: [
            for (final n in _networks)
              DropdownMenuItem(value: n.value, child: Text(n.label)),
          ],
          onChanged: (value) => setState(() => _network = value!),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: _isCharging ? null : _pay,
          child: _isCharging
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                )
              : const Text('Pay via Mobile Money'),
        ),
        if (_isPolling) ...[
          const SizedBox(height: 16),
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: 16,
                width: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('Waiting for confirmation...'),
            ],
          ),
        ],
        if (_message != null) ...[
          const SizedBox(height: 14),
          Text(
            _message!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.success,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
        if (_error != null) ...[
          const SizedBox(height: 14),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.danger),
          ),
        ],
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: _isPolling ? null : _refreshStatus,
            child: const Text('Already paid? Check again'),
          ),
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
