import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';

/// A small, non-interactive Google Maps preview showing pickup and/or
/// drop-off pins. Embedded inline in a scrollable page, so every gesture
/// is disabled - it's for looking at, not panning/zooming. Wrapped in
/// [IgnorePointer]: the `*GesturesEnabled: false` flags below stop the map
/// itself from reacting to a touch, but `google_maps_flutter`'s underlying
/// native Android view can still fight an ancestor scrollable for a drag
/// that starts over it - a known google_maps_flutter issue. IgnorePointer
/// stops Flutter from routing any pointer event into the platform view at
/// all, so a scroll that starts here is never contested.
class MapPreview extends StatelessWidget {
  const MapPreview({super.key, this.pickup, this.dropoff, this.height = 180});

  final LatLng? pickup;
  final LatLng? dropoff;
  final double height;

  @override
  Widget build(BuildContext context) {
    final points = [?pickup, ?dropoff];
    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No location set')),
      );
    }

    final center = points.length == 1
        ? points.first
        : LatLng(
            (points.first.latitude + points.last.latitude) / 2,
            (points.first.longitude + points.last.longitude) / 2,
          );

    return IgnorePointer(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: height,
          child: gmap.GoogleMap(
            initialCameraPosition: gmap.CameraPosition(
              target: gmap.LatLng(center.latitude, center.longitude),
              zoom: points.length == 1 ? 14 : 12,
            ),
            zoomGesturesEnabled: false,
            scrollGesturesEnabled: false,
            rotateGesturesEnabled: false,
            tiltGesturesEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            markers: {
              if (pickup != null)
                gmap.Marker(
                  markerId: const gmap.MarkerId('pickup'),
                  position: gmap.LatLng(pickup!.latitude, pickup!.longitude),
                  icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                    gmap.BitmapDescriptor.hueAzure,
                  ),
                ),
              if (dropoff != null)
                gmap.Marker(
                  markerId: const gmap.MarkerId('dropoff'),
                  position: gmap.LatLng(dropoff!.latitude, dropoff!.longitude),
                ),
            },
            polylines: {
              if (pickup != null && dropoff != null)
                gmap.Polyline(
                  polylineId: const gmap.PolylineId('route'),
                  points: [
                    gmap.LatLng(pickup!.latitude, pickup!.longitude),
                    gmap.LatLng(dropoff!.latitude, dropoff!.longitude),
                  ],
                  width: 3,
                  color: AppTheme.primary.withValues(alpha: 0.6),
                ),
            },
          ),
        ),
      ),
    );
  }
}
