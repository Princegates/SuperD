import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/features/driver/providers/driver_providers.dart';
import 'package:superd/features/driver/screens/driver_dashboard_screen.dart';
import 'package:superd/models/app_settings.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/delivery_status.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/user_role.dart';
import 'package:superd/shared/widgets/delivery_card.dart';

/// The driver dashboard's header used to be five stacked full-width
/// blocks - availability, revenue, and a four-row commission banner with
/// its own button - before the first delivery. These pin down that the
/// header stays compact on a small phone, that nothing overflows once the
/// balance chip sits beside the revenue on one line, and that the
/// finished pile can't push active work off the screen.

const _driver = Profile(
  id: 'driver-1',
  email: 'nii@example.com',
  fullName: 'nii',
  role: UserRole.driver,
  phone: '+233240000000',
  isOnline: true,
);

Delivery _finished(int i) => Delivery(
  id: 'done-$i',
  trackingCode: 'DONE$i',
  status: DeliveryStatus.delivered,
  customerName: 'Customer $i',
  pickupAddress: 'Pickup $i',
  dropoffAddress: 'Naa Adokailey Street, Sempe, Accra, Ablekuma South',
  createdAt: DateTime(2026, 9, 13, 2, i % 24),
  updatedAt: DateTime(2026, 9, 13, 2, i % 24),
  assignedDriverId: _driver.id,
);

Delivery _active() => Delivery(
  id: 'active-1',
  trackingCode: 'ACTIVE1',
  status: DeliveryStatus.assigned,
  customerName: 'Waiting Customer',
  pickupAddress: 'Pickup',
  dropoffAddress: '14, Dr. Isert Street, North Ridge, Accra',
  createdAt: DateTime(2026, 9, 13, 3),
  updatedAt: DateTime(2026, 9, 13, 3),
  assignedDriverId: _driver.id,
);

/// initState kicks off live location sharing. Geolocator has no
/// implementation under `flutter test`, so stand in for its channel and
/// report location services off - the first thing _startSharingLocation
/// checks, and enough for it to bail out before touching anything else.
void _stubGeolocator() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (call) async =>
            call.method == 'isLocationServiceEnabled' ? false : null,
      );
}

Widget _dashboard({
  required List<Delivery> deliveries,
  required double balanceDue,
}) {
  return ProviderScope(
    overrides: [
      currentProfileProvider.overrideWith((ref) => Stream.value(_driver)),
      myDeliveriesProvider.overrideWith((ref) => Stream.value(deliveries)),
      appSettingsProvider.overrideWith(
        (ref) => Stream.value(
          const AppSettings(
            currency: 'GHS',
            theme: 'navy_gold',
            allowDriverWebLogin: true,
            baseFare: 5,
            pricePerKm: 1.5,
          ),
        ),
      ),
      dailyFeeTiersProvider.overrideWith((ref) => Stream.value([])),
      freeDayBalanceProvider.overrideWith((ref) => Stream.value(0)),
      myVisibleNoticesProvider.overrideWith((ref) => Stream.value([])),
      totalCommissionDueProvider.overrideWithValue(balanceDue),
      commissionDueAmountProvider.overrideWithValue(balanceDue),
      dailyFeeLatestAttemptProvider.overrideWithValue(null),
      todaysRevenueProvider.overrideWithValue(100),
    ],
    child: const MaterialApp(home: DriverDashboardScreen()),
  );
}

void main() {
  setUp(_stubGeolocator);

  testWidgets('balance sits on one line with revenue, and nothing overflows', (
    tester,
  ) async {
    // A small phone - the width where a Row of revenue + chip is most
    // likely to overflow.
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _dashboard(deliveries: [_active()], balanceDue: 9),
    );
    await tester.pumpAndSettle();

    // A RenderFlex overflow reports itself as a test exception, so simply
    // getting here clean is the assertion. Confirm the pieces are present.
    expect(find.textContaining('Today: GHS 100.00'), findsOneWidget);
    expect(find.textContaining('Pay GHS 9.00'), findsOneWidget);
    expect(
      find.textContaining('Pay to keep receiving new deliveries'),
      findsOneWidget,
    );
  });

  testWidgets('the first delivery is visible without scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _dashboard(deliveries: [_active()], balanceDue: 9),
    );
    await tester.pumpAndSettle();

    final firstCard = tester.getTopLeft(find.byType(DeliveryCard).first);
    // Measured against this same test: the stacked-bands header put the
    // first card at dy=408 on a 640-tall screen - 64% of the viewport gone
    // before any delivery. The merged header puts it at 236. The bound
    // here is a regression guard with a little headroom, not a target;
    // if it trips, the header has grown back.
    expect(
      firstCard.dy,
      lessThan(260),
      reason: 'header should leave the first delivery visible on a small '
          'phone (was 408 before the header was merged), got '
          'dy=${firstCard.dy}',
    );
  });

  testWidgets('no balance means no chip and no blocking note', (tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _dashboard(deliveries: [_active()], balanceDue: 0),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Pay GHS'), findsNothing);
    expect(
      find.textContaining('Pay to keep receiving new deliveries'),
      findsNothing,
    );
    expect(find.textContaining('Today: GHS 100.00'), findsOneWidget);
  });

  testWidgets('finished deliveries are capped, with a link to My rides', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _dashboard(
        deliveries: [_active(), for (var i = 0; i < 8; i++) _finished(i)],
        balanceDue: 0,
      ),
    );
    await tester.pumpAndSettle();

    // 1 active + at most 3 completed, not all 9.
    expect(find.byType(DeliveryCard), findsNWidgets(4));
    expect(find.text('See all 8 in My rides'), findsOneWidget);
  });
}
