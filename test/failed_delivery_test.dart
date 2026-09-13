import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/delivery_failure_reason.dart';
import 'package:superd/models/delivery_status.dart';
import 'package:superd/shared/widgets/status_badge.dart';

/// A failed delivery and a cancelled one are the same row in Postgres -
/// both `cancelled`, separated only by `failure_reason` (see
/// `0089_failed_delivery_outcome.sql`). Everything below exists to stop
/// them collapsing back into the same thing on screen, which is the
/// confusion the outcome was added to end.

Delivery _delivery({
  DeliveryStatus status = DeliveryStatus.cancelled,
  DeliveryFailureReason? reason,
  String? note,
}) {
  final now = DateTime.now();
  return Delivery(
    id: 'd1',
    trackingCode: 'SD9001',
    status: status,
    customerName: 'Ama Owusu',
    pickupAddress: 'Osu',
    dropoffAddress: 'East Legon',
    createdAt: now,
    updatedAt: now,
    failureReason: reason,
    failureNote: note,
    failedAt: reason == null ? null : now,
  );
}

void main() {
  test('a cancelled delivery and a failed one do not read the same', () {
    final calledOff = _delivery();
    final failed = _delivery(reason: DeliveryFailureReason.customerAbsent);

    expect(calledOff.didFail, isFalse);
    expect(calledOff.outcomeLabel, 'Cancelled');

    expect(failed.didFail, isTrue);
    expect(failed.outcomeLabel, 'Failed - Customer absent');
    expect(failed.outcomeLabel, isNot(calledOff.outcomeLabel));
    expect(failed.outcomeColor, isNot(calledOff.outcomeColor));
  });

  test('the reason survives a round trip through the wire format', () {
    for (final reason in DeliveryFailureReason.values) {
      expect(
        DeliveryFailureReason.fromString(reason.wireValue),
        reason,
        reason: '${reason.name} did not survive its own wire value',
      );
    }
  });

  test('a reason this build has never heard of is not a crash', () {
    // A value added to the Postgres enum before the app ships is the
    // realistic case. A rider mid-shift gets "no reason shown", not a
    // broken screen.
    expect(DeliveryFailureReason.fromString('rider_overslept'), isNull);
    expect(DeliveryFailureReason.fromString(null), isNull);
  });

  test('a failed delivery is read from the row the server actually sends', () {
    final delivery = Delivery.fromMap({
      'id': 'd1',
      'tracking_code': 'SD9001',
      'status': 'cancelled',
      'customer_name': 'Ama Owusu',
      'pickup_address': 'Osu',
      'dropoff_address': 'East Legon',
      'created_at': '2026-09-13T10:00:00Z',
      'updated_at': '2026-09-13T11:00:00Z',
      'failure_reason': 'wrong_address',
      'failure_note': 'No house 14 on that street.',
      'failed_at': '2026-09-13T11:00:00Z',
    });

    expect(delivery.status, DeliveryStatus.cancelled);
    expect(delivery.failureReason, DeliveryFailureReason.wrongAddress);
    expect(delivery.failureNote, 'No house 14 on that street.');
    expect(delivery.didFail, isTrue);
  });

  test('hiding the pickup on a finished job keeps why it finished', () {
    // Riders see their history with the vendor's identity stripped out.
    // The reason they themselves recorded must survive that, or their own
    // completed work stops explaining itself back to them.
    final hidden = _delivery(
      reason: DeliveryFailureReason.customerRefused,
      note: 'Said they never ordered it.',
    ).withPickupHiddenIfHistory;

    expect(hidden.pickupAddress, 'Pickup details hidden');
    expect(hidden.failureReason, DeliveryFailureReason.customerRefused);
    expect(hidden.failureNote, 'Said they never ordered it.');
  });

  testWidgets('the badge says Failed, not Cancelled', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StatusBadge(
            status: DeliveryStatus.cancelled,
            failureReason: DeliveryFailureReason.unreachable,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Failed'), findsOneWidget);
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('and still says Cancelled when that is what happened', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: StatusBadge(status: DeliveryStatus.cancelled)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cancelled'), findsOneWidget);
  });
}
