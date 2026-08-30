import 'package:flutter_test/flutter_test.dart';

import 'package:superd/features/driver/utils/route_optimizer.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/delivery_status.dart';
import 'package:superd/models/route_stop.dart';

Delivery _delivery({
  required String id,
  required DeliveryStatus status,
  double? pickupLat,
  double? pickupLng,
  double? dropoffLat,
  double? dropoffLng,
}) {
  final now = DateTime(2026);
  return Delivery(
    id: id,
    trackingCode: id.toUpperCase(),
    status: status,
    customerName: 'Test customer',
    pickupAddress: '$id pickup address',
    pickupLat: pickupLat,
    pickupLng: pickupLng,
    dropoffAddress: '$id dropoff address',
    dropoffLat: dropoffLat,
    dropoffLng: dropoffLng,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('optimizeDriverRoute', () {
    test('an unaccepted delivery contributes a pickup then its drop-off', () {
      final delivery = _delivery(
        id: 'a',
        status: DeliveryStatus.assigned,
        pickupLat: 5.6,
        pickupLng: -0.2,
        dropoffLat: 5.7,
        dropoffLng: -0.3,
      );

      final stops = optimizeDriverRoute([delivery]);

      expect(stops, hasLength(2));
      expect(stops[0].type, RouteStopType.pickup);
      expect(stops[1].type, RouteStopType.dropoff);
    });

    test('an already-picked-up delivery only contributes its drop-off', () {
      final delivery = _delivery(
        id: 'a',
        status: DeliveryStatus.pickedUp,
        pickupLat: 5.6,
        pickupLng: -0.2,
        dropoffLat: 5.7,
        dropoffLng: -0.3,
      );

      final stops = optimizeDriverRoute([delivery]);

      expect(stops, hasLength(1));
      expect(stops.single.type, RouteStopType.dropoff);
    });

    test('pending/delivered/cancelled deliveries contribute no stops', () {
      final stops = optimizeDriverRoute([
        _delivery(
          id: 'p',
          status: DeliveryStatus.pending,
          pickupLat: 5.6,
          pickupLng: -0.2,
          dropoffLat: 5.7,
          dropoffLng: -0.3,
        ),
        _delivery(
          id: 'd',
          status: DeliveryStatus.delivered,
          pickupLat: 5.6,
          pickupLng: -0.2,
          dropoffLat: 5.7,
          dropoffLng: -0.3,
        ),
        _delivery(
          id: 'c',
          status: DeliveryStatus.cancelled,
          pickupLat: 5.6,
          pickupLng: -0.2,
          dropoffLat: 5.7,
          dropoffLng: -0.3,
        ),
      ]);

      expect(stops, isEmpty);
    });

    test('a delivery missing coordinates is skipped without crashing', () {
      final stops = optimizeDriverRoute([
        _delivery(id: 'a', status: DeliveryStatus.assigned),
      ]);

      expect(stops, isEmpty);
    });

    test('visits the nearest reachable stop first from the start point', () {
      // Two already-picked-up deliveries (so both drop-offs are
      // immediately reachable, no pickup-first constraint in the way) -
      // "far" is much further from the start point than "near".
      final near = _delivery(
        id: 'near',
        status: DeliveryStatus.pickedUp,
        dropoffLat: 5.601,
        dropoffLng: -0.201,
      );
      final far = _delivery(
        id: 'far',
        status: DeliveryStatus.pickedUp,
        dropoffLat: 6.5,
        dropoffLng: -1.5,
      );

      final stops = optimizeDriverRoute(
        [far, near],
        startLat: 5.6,
        startLng: -0.2,
      );

      expect(stops.map((s) => s.delivery.id), ['near', 'far']);
    });

    test(
      'proximity alone decides order - being already picked up is not '
      'given priority over a closer pickup',
      () {
        // "assigned" hasn't been picked up yet, but its pickup point sits
        // right next to the start - closer than "picked"'s drop-off, even
        // though "picked" is already in hand. Nearest-neighbor visits
        // assigned's pickup first purely because it's closer, then picked's
        // drop-off, then finally assigned's own drop-off (unlocked only
        // once its pickup was visited).
        final picked = _delivery(
          id: 'picked',
          status: DeliveryStatus.pickedUp,
          dropoffLat: 5.65,
          dropoffLng: -0.25,
        );
        final assigned = _delivery(
          id: 'assigned',
          status: DeliveryStatus.assigned,
          pickupLat: 5.601,
          pickupLng: -0.201,
          dropoffLat: 5.9,
          dropoffLng: -0.5,
        );

        final stops = optimizeDriverRoute(
          [picked, assigned],
          startLat: 5.6,
          startLng: -0.2,
        );

        expect(stops.map((s) => s.delivery.id), [
          'assigned',
          'picked',
          'assigned',
        ]);
        expect(stops[0].type, RouteStopType.pickup);
        expect(stops[1].type, RouteStopType.dropoff);
        expect(stops[2].type, RouteStopType.dropoff);
      },
    );

    test('with no start point, stops are visited in their given order', () {
      final a = _delivery(
        id: 'a',
        status: DeliveryStatus.pickedUp,
        dropoffLat: 10,
        dropoffLng: 10,
      );
      final b = _delivery(
        id: 'b',
        status: DeliveryStatus.pickedUp,
        dropoffLat: 0,
        dropoffLng: 0,
      );

      final stops = optimizeDriverRoute([a, b]);

      expect(stops.map((s) => s.delivery.id), ['a', 'b']);
    });
  });
}
