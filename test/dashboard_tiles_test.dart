import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/features/admin/providers/admin_providers.dart';
import 'package:superd/features/admin/screens/home_screen.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/user_role.dart';

/// The summary tiles each carried a hardcoded width of 160. A 360dp phone
/// leaves 320dp inside the page padding, and two of them plus the 12dp gap
/// need 332 - twelve pixels short, so every tile took a row to itself and
/// the dashboard ran off the bottom with half the width blank.
///
/// Twelve pixels is exactly the kind of thing that comes back, so these
/// pin the behaviour rather than the number.

const _admin = Profile(
  id: 'staff-1',
  email: 'dispatch@superdeliverygh.com',
  fullName: 'Dispatch',
  role: UserRole.superAdmin,
  isActive: true,
);

Profile _adminNamed(String name) => Profile(
  id: 'staff-1',
  email: 'dispatch@superdeliverygh.com',
  fullName: name,
  role: UserRole.superAdmin,
  isActive: true,
);

Widget _screen({String? staffName}) {
  return ProviderScope(
    overrides: [
      currentProfileProvider.overrideWith(
        (ref) =>
            Stream.value(staffName == null ? _admin : _adminNamed(staffName)),
      ),
      allDeliveriesProvider.overrideWith((ref) => Stream.value(<Delivery>[])),
      driversListProvider.overrideWith((ref) async => <Profile>[]),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: HomeScreen(quickLinks: const [], onNavigate: (_) {}),
      ),
    ),
  );
}

Future<void> _pumpAt(
  WidgetTester tester,
  Size size, {
  String? staffName,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_screen(staffName: staffName));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a phone shows two tiles to a row, not one', (tester) async {
    // 360dp wide - a common, and close to the narrowest realistic, handset.
    await _pumpAt(tester, const Size(360, 1200));

    final first = tester.getTopLeft(find.text("Today's deliveries"));
    final second = tester.getTopLeft(find.text('Pending'));

    expect(
      second.dy,
      first.dy,
      reason: 'the first two tiles should share a row',
    );
    expect(second.dx, greaterThan(first.dx));
  });

  testWidgets('no tile is wider than the screen at 320dp', (tester) async {
    await _pumpAt(tester, const Size(320, 1200));

    for (final label in ["Today's deliveries", 'Pending', 'Riders online']) {
      final box = tester.getRect(find.text(label));
      expect(box.right, lessThanOrEqualTo(320));
    }
  });

  testWidgets('a wide window spreads out but does not go thin', (tester) async {
    await _pumpAt(tester, const Size(1400, 1200));

    final row = <double>[
      tester.getTopLeft(find.text("Today's deliveries")).dy,
      tester.getTopLeft(find.text('Pending')).dy,
      tester.getTopLeft(find.text('In progress')).dy,
    ];
    // Three across, capped there - six tiles land as two even rows rather
    // than one thin line with nothing under it.
    expect(row.toSet().length, 1);
    expect(
      tester.getTopLeft(find.text('Delivered today')).dy,
      greaterThan(row.first),
    );
  });

  testWidgets('the brand header fits, however long the name is', (
    tester,
  ) async {
    // Renaming SuperD to SuperDelivery more than doubled the width of this
    // heading and pushed the header off a 360dp screen - a real overflow
    // that shipped in a commit before this test existed. A long staff name
    // is the other half of the same squeeze.
    await _pumpAt(
      tester,
      const Size(320, 1200),
      staffName: 'Emmanuella Nana Ama Owusu-Ansah',
    );

    expect(tester.takeException(), isNull);
    expect(find.text('SuperDelivery'), findsOneWidget);
  });
}
