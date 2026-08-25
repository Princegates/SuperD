import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../core/theme/app_theme.dart';

/// A small, non-interactive OpenStreetMap preview showing pickup and/or
/// drop-off pins. Uses the public OSM tile server — free, no API key.
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: height,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: points.length == 1 ? 14 : 12,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.drag,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.superd.app',
            ),
            if (pickup != null && dropoff != null)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: [pickup!, dropoff!],
                    strokeWidth: 3,
                    color: AppTheme.primary.withValues(alpha: 0.6),
                  ),
                ],
              ),
            MarkerLayer(
              markers: [
                if (pickup != null)
                  Marker(
                    point: pickup!,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.trip_origin,
                      color: AppTheme.primary,
                    ),
                  ),
                if (dropoff != null)
                  Marker(
                    point: dropoff!,
                    width: 34,
                    height: 34,
                    child: const Icon(
                      Icons.place,
                      color: AppTheme.danger,
                      size: 34,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
