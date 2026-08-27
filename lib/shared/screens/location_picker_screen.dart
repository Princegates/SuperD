import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart';

import '../utils/geocode_search.dart';

/// Full-screen map for picking a point that isn't the device's own
/// location - e.g. a dispatcher marking where a customer actually is, or a
/// customer picking their own delivery address. Returns the picked
/// [LatLng] via [Navigator.pop], or null if cancelled.
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
  final _searchController = TextEditingController();
  LatLng? _picked;
  List<GeocodeResult> _searchResults = const [];
  bool _isSearching = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _picked = widget.initialCenter;
    // First time opening the picker (nothing set yet) - try to place the
    // pin at the device's own location right away, same as tapping "Use
    // my location" manually. Editing an already-set point skips this, so
    // re-opening the picker never silently overwrites what's there.
    if (widget.initialCenter == null) _useMyLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _moveCamera(LatLng target, {double zoom = 15}) async {
    final controller = await _controller.future;
    await controller.animateCamera(
      gmap.CameraUpdate.newLatLngZoom(
        gmap.LatLng(target.latitude, target.longitude),
        zoom,
      ),
    );
  }

  /// Places the pin at the device's own current location - called both
  /// automatically on first opening the picker (see initState) and from
  /// the explicit "Use my location" button, so retrying after an initial
  /// denial works the same way as the first attempt.
  Future<void> _useMyLocation() async {
    setState(() => _isLocating = true);
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Location permission is off - allow it, or just tap the "
                'map instead.',
              ),
            ),
          );
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final here = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      await _moveCamera(here);
      setState(() {
        _picked = here;
        _searchResults = const [];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't get your current location")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _search() async {
    final query = _searchController.text;
    if (query.trim().isEmpty) return;
    setState(() => _isSearching = true);
    final results = await searchAddress(query);
    if (!mounted) return;
    setState(() {
      _searchResults = results;
      _isSearching = false;
    });
    if (results.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matches for that address')),
      );
    }
  }

  Future<void> _selectResult(GeocodeResult result) async {
    await _moveCamera(result.location);
    setState(() {
      _picked = result.location;
      _searchResults = const [];
      _searchController.text = result.displayName;
    });
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
            onTap: (point) => setState(() {
              _picked = LatLng(point.latitude, point.longitude);
              _searchResults = const [];
            }),
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
            top: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Type an address to search',
                            ),
                            onSubmitted: (_) => _search(),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Search',
                          icon: _isSearching
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search),
                          onPressed: _isSearching ? null : _search,
                        ),
                        IconButton(
                          tooltip: 'Use my current location',
                          icon: _isLocating
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.my_location),
                          onPressed: _isLocating ? null : _useMyLocation,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Card(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined),
                            title: Text(
                              result.displayName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => _selectResult(result),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
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
                      ? 'Search an address, use your location, or tap the '
                            'map to drop a pin - then confirm.'
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
