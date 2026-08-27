import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmap;

import '../../../models/profile.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

/// The "Live Map" section of the admin dashboard shell - every driver
/// currently sharing their position (app open, location granted, updated
/// within the last 15 minutes - see [Profile.hasRecentLocation]) shown as a
/// marker, live via realtime. A driver who closes the app or loses
/// permission just drops off the map once their last update goes stale;
/// nothing is ever deleted server-side.
class LiveMapScreen extends ConsumerWidget {
  const LiveMapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final driversState = ref.watch(driverLocationsProvider);

    return AsyncValueView<List<Profile>>(
      value: driversState,
      data: (allDrivers) {
        final live = allDrivers.where((d) => d.hasRecentLocation).toList();

        if (live.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No drivers are currently sharing their location.\n'
                'A driver shows up here while their app is open and '
                'location is granted.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ),
          );
        }

        final center = live.first;
        return gmap.GoogleMap(
          initialCameraPosition: gmap.CameraPosition(
            target: gmap.LatLng(center.lastLat!, center.lastLng!),
            zoom: 12,
          ),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          markers: {
            for (final driver in live)
              gmap.Marker(
                markerId: gmap.MarkerId(driver.id),
                position: gmap.LatLng(driver.lastLat!, driver.lastLng!),
                icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
                  gmap.BitmapDescriptor.hueAzure,
                ),
                infoWindow: gmap.InfoWindow(
                  title: driver.displayName,
                  snippet: _lastSeenLabel(driver.locationUpdatedAt!),
                ),
              ),
          },
        );
      },
    );
  }

  String _lastSeenLabel(DateTime updatedAt) {
    final secondsAgo = DateTime.now().difference(updatedAt).inSeconds;
    if (secondsAgo < 60) return 'Updated just now';
    final minutesAgo = secondsAgo ~/ 60;
    return 'Updated $minutesAgo min${minutesAgo == 1 ? '' : 's'} ago';
  }
}
