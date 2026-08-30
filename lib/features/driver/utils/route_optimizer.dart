import 'package:geolocator/geolocator.dart';

import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/route_stop.dart';

/// Greedy nearest-neighbor ordering of a driver's outstanding pickup/
/// drop-off stops across every active delivery assigned to them, so a
/// driver carrying several parcels at once (see the simultaneous-
/// deliveries-per-driver cap in `0048_manual_assignment_cap.sql`) gets
/// one sensible visiting order instead of an unordered list. This
/// doesn't change how deliveries are stored, assigned, or worked one at
/// a time - it's a planning aid layered on top of what's already there
/// (see the driver's "My route" screen); the dashboard's own
/// per-delivery list and every existing accept/pickup/deliver flow are
/// untouched.
///
/// Not a true travelling-salesman solve - just "always go to whichever
/// reachable stop is closest right now". That's the standard, cheap
/// heuristic for this: exact TSP doesn't scale and isn't worth it for
/// the handful of stops one driver ever actually carries at once.
///
/// A delivery not yet picked up (`assigned`/`in_transit`) contributes
/// both a pickup and a drop-off stop, but its drop-off only becomes
/// reachable once its own pickup has been visited in this same ordering
/// - a driver can't drop off a package they haven't collected yet. A
/// delivery already picked up (`picked_up`) contributes only its
/// drop-off. [startLat]/[startLng] (the driver's last known position, if
/// any) seed where the route "starts from"; left null, stops are
/// visited in whatever order they were passed in.
List<RouteStop> optimizeDriverRoute(
  List<Delivery> deliveries, {
  double? startLat,
  double? startLng,
}) {
  final reachable = <RouteStop>[];
  final awaitingPickup = <String, RouteStop>{};

  for (final delivery in deliveries) {
    switch (delivery.status) {
      case DeliveryStatus.assigned:
      case DeliveryStatus.inTransit:
        if (delivery.hasPickupCoordinates) {
          reachable.add(
            RouteStop(
              delivery: delivery,
              type: RouteStopType.pickup,
              lat: delivery.pickupLat!,
              lng: delivery.pickupLng!,
              address: delivery.pickupAddress,
            ),
          );
        }
        if (delivery.hasDropoffCoordinates) {
          awaitingPickup[delivery.id] = RouteStop(
            delivery: delivery,
            type: RouteStopType.dropoff,
            lat: delivery.dropoffLat!,
            lng: delivery.dropoffLng!,
            address: delivery.dropoffAddress,
          );
        }
        break;
      case DeliveryStatus.pickedUp:
        if (delivery.hasDropoffCoordinates) {
          reachable.add(
            RouteStop(
              delivery: delivery,
              type: RouteStopType.dropoff,
              lat: delivery.dropoffLat!,
              lng: delivery.dropoffLng!,
              address: delivery.dropoffAddress,
            ),
          );
        }
        break;
      case DeliveryStatus.pending:
      case DeliveryStatus.delivered:
      case DeliveryStatus.cancelled:
        break;
    }
  }

  final ordered = <RouteStop>[];
  var currentLat = startLat;
  var currentLng = startLng;

  double distanceFrom(RouteStop stop) =>
      Geolocator.distanceBetween(currentLat!, currentLng!, stop.lat, stop.lng);

  while (reachable.isNotEmpty) {
    final next = (currentLat == null || currentLng == null)
        ? reachable.first
        : reachable.reduce(
            (a, b) => distanceFrom(a) <= distanceFrom(b) ? a : b,
          );

    reachable.remove(next);
    ordered.add(next);
    currentLat = next.lat;
    currentLng = next.lng;

    if (next.isPickup) {
      final dropoff = awaitingPickup.remove(next.delivery.id);
      if (dropoff != null) reachable.add(dropoff);
    }
  }

  return ordered;
}
