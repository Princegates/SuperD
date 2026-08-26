import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart';

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
  final Completer<gmap.GoogleMapController> _controller = Completer();
  LatLng? _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialCenter;
    if (widget.initialCenter == null) _centerOnDeviceLocation();
  }

  Future<void> _centerOnDeviceLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final controller = await _controller.future;
      await controller.animateCamera(
        gmap.CameraUpdate.newLatLngZoom(
          gmap.LatLng(position.latitude, position.longitude),
          15,
        ),
      );
    } catch (_) {
      // No luck getting a starting point - the dispatcher can just pan/zoom.
    }
  }

  @override
  Widget build(BuildContext context) {
    final initial = widget.initialCenter ?? const LatLng(0, 0);

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
          gmap.GoogleMap(
            initialCameraPosition: gmap.CameraPosition(
              target: gmap.LatLng(initial.latitude, initial.longitude),
              zoom: widget.initialCenter != null ? 15 : 2,
            ),
            onMapCreated: (controller) {
              if (!_controller.isCompleted) _controller.complete(controller);
            },
            onTap: (point) =>
                setState(() => _picked = LatLng(point.latitude, point.longitude)),
            markers: {
              if (_picked != null)
                gmap.Marker(
                  markerId: const gmap.MarkerId('picked'),
                  position: gmap.LatLng(_picked!.latitude, _picked!.longitude),
                ),
            },
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
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
