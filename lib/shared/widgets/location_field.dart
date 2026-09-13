import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';
import '../screens/location_picker_screen.dart';
import '../utils/geocode_search.dart';
import '../utils/reverse_geocode.dart';
import 'address_autocomplete_field.dart';

/// The "where?" question, asked once, the same way on both public forms.
///
/// Three ways to answer it, because the right one depends entirely on who
/// is filling the form: type it (with as-you-type suggestions), tap **Use
/// my location** when you're standing at the place, or drop a pin when you
/// can't name the street - which, for a lot of Ghanaian addresses, is the
/// normal case rather than the exception.
///
/// Both forms previously offered only the first and third, with the map as
/// a small text link under the field. A customer ordering to where they
/// already are had to describe it instead of just saying "here".
class LocationField extends StatefulWidget {
  const LocationField({
    super.key,
    required this.controller,
    required this.label,
    required this.mapTitle,
    required this.onPicked,
    required this.hasLocation,
    this.helperText,
    this.confirmedHint,
    this.validator,
    this.initialCenter,
  });

  final TextEditingController controller;
  final String label;
  final String? helperText;

  /// Title shown on the full-screen map picker.
  final String mapTitle;

  /// Fires whenever a real coordinate is settled on, by any of the three
  /// routes. The caller owns the lat/lng and whatever it triggers (a price
  /// estimate refresh, say).
  final void Function(double lat, double lng) onPicked;

  /// Whether the caller currently holds a coordinate - drives the
  /// confirmation line, so the person can see the answer landed rather
  /// than guessing from the text in the box.
  final bool hasLocation;

  /// Shown beside the tick once [hasLocation] is true.
  final String? confirmedHint;

  final FormFieldValidator<String>? validator;
  final LatLng? initialCenter;

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  bool _isLocating = false;
  bool _isResolvingPin = false;
  String? _locateError;

  bool get _busy => _isLocating || _isResolvingPin;

  /// Fills the field from the device's own position. On the web this is
  /// the browser's geolocation prompt (and needs HTTPS); on a phone it's
  /// the usual OS permission dialog. Every failure path ends in a readable
  /// line under the field rather than a dead button - "nothing happened"
  /// is the worst possible answer to tapping this.
  Future<void> _useCurrentLocation() async {
    setState(() {
      _isLocating = true;
      _locateError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw const _LocateFailure(
          'Location permission was declined. Type the address or drop a '
          'pin instead.',
        );
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocateFailure(
          'Location is blocked for this site in your browser or phone '
          'settings. Type the address or drop a pin instead.',
        );
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      widget.onPicked(position.latitude, position.longitude);

      final address = await reverseGeocode(
        position.latitude,
        position.longitude,
      );
      if (!mounted) return;
      setState(() {
        widget.controller.text =
            address ?? _coords(position.latitude, position.longitude);
      });
    } on _LocateFailure catch (e) {
      if (mounted) setState(() => _locateError = e.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _locateError =
              "Couldn't get your location just now. Type the address or "
              'drop a pin instead.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _pinOnMap() async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) => LocationPickerScreen(
          title: widget.mapTitle,
          initialCenter: widget.initialCenter,
        ),
      ),
    );
    if (picked == null || !mounted) return;

    widget.onPicked(picked.latitude, picked.longitude);
    setState(() {
      _isResolvingPin = true;
      _locateError = null;
    });

    final address = await reverseGeocode(picked.latitude, picked.longitude);
    if (!mounted) return;
    setState(() {
      widget.controller.text =
          address ?? _coords(picked.latitude, picked.longitude);
      _isResolvingPin = false;
    });
  }

  static String _coords(double lat, double lng) =>
      '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';

  void _onSuggestion(GeocodeResult result) {
    setState(() => _locateError = null);
    widget.onPicked(result.location.latitude, result.location.longitude);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AddressAutocompleteField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.helperText,
            prefixIcon: const Icon(Icons.location_on_outlined, size: 20),
          ),
          validator: widget.validator,
          onPlaceSelected: _onSuggestion,
        ),
        const SizedBox(height: 10),
        // Wrap, not Row: at ~320dp these two don't fit side by side, and a
        // squeezed pair of buttons is worse than a stacked pair.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _LocationAction(
              icon: Icons.my_location,
              label: 'Use my location',
              busy: _isLocating,
              onPressed: _busy ? null : _useCurrentLocation,
              emphasised: true,
            ),
            _LocationAction(
              icon: Icons.map_outlined,
              label: 'Pin on map',
              busy: _isResolvingPin,
              onPressed: _busy ? null : _pinOnMap,
            ),
          ],
        ),
        if (_locateError != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, size: 15, color: AppTheme.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _locateError!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.warning,
                  ),
                ),
              ),
            ],
          ),
        ] else if (widget.hasLocation && widget.confirmedHint != null) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.check_circle,
                size: 15,
                color: AppTheme.success,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.confirmedHint!,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LocationAction extends StatelessWidget {
  const _LocationAction({
    required this.icon,
    required this.label,
    required this.busy,
    required this.onPressed,
    this.emphasised = false,
  });

  final IconData icon;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  final bool emphasised;

  @override
  Widget build(BuildContext context) {
    final child = busy
        ? const SizedBox(
            height: 15,
            width: 15,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 17);
    final style = ButtonStyle(
      padding: WidgetStatePropertyAll(
        const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      visualDensity: VisualDensity.compact,
    );

    return emphasised
        ? FilledButton.tonalIcon(
            onPressed: onPressed,
            icon: child,
            label: Text(label),
            style: style,
          )
        : OutlinedButton.icon(
            onPressed: onPressed,
            icon: child,
            label: Text(label),
            style: style,
          );
  }
}

class _LocateFailure implements Exception {
  const _LocateFailure(this.message);
  final String message;
}
