import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';

/// Full-screen map for picking a point that isn't the device's own
/// location - e.g. a dispatcher marking where a customer actually is.
/// Returns the picked [LatLng] via [Navigator.pop], or null if cancelled.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    this.initialCenter,
    this.title = 'Pick a location',
  });

  final LatLng? initialCenter;
  final String title;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  LatLng? _picked;
  LatLng? _initialCenter;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialCenter;
    _initialCenter = widget.initialCenter;
    if (_initialCenter == null) _centerOnDeviceLocation();
  }

  Future<void> _centerOnDeviceLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(
          () => _initialCenter = LatLng(position.latitude, position.longitude),
        );
      }
    } catch (_) {
      // No luck getting a starting point - the dispatcher can just pan/zoom.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _picked == null
                ? null
                : () => Navigator.pop(context, _picked),
            child: Text(
              'Confirm',
              style: TextStyle(
                color: _picked == null ? Colors.white54 : Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: _initialCenter ?? const LatLng(0, 0),
              initialZoom: _initialCenter != null ? 15 : 2,
              onTap: (tapPosition, point) => setState(() => _picked = point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.superd.app',
              ),
              if (_picked != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _picked!,
                      width: 44,
                      height: 44,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        color: AppTheme.danger,
                        size: 44,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(
                  _picked == null
                      ? 'Tap the map to drop a pin, then confirm.'
                      : 'Pinned: ${_picked!.latitude.toStringAsFixed(5)}, '
                            '${_picked!.longitude.toStringAsFixed(5)}',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
