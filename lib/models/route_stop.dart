import 'delivery.dart';

enum RouteStopType { pickup, dropoff }

/// One point in a driver's planned route - either the pickup or the
/// drop-off half of a single [delivery]. Purely a client-side planning
/// concept (see `optimizeDriverRoute()`), never persisted - a delivery's
/// own pickup/drop-off address and coordinates are always the source of
/// truth.
class RouteStop {
  const RouteStop({
    required this.delivery,
    required this.type,
    required this.lat,
    required this.lng,
    required this.address,
  });

  final Delivery delivery;
  final RouteStopType type;
  final double lat;
  final double lng;
  final String address;

  bool get isPickup => type == RouteStopType.pickup;
}
