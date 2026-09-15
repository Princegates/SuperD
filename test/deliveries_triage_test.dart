import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/features/admin/providers/admin_providers.dart';
import 'package:superd/features/admin/screens/admin_dashboard_screen.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/delivery_status.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/user_role.dart';

/// The Deliveries screen gained the two things a dispatcher does all day:
/// find one order among many, and notice the ones that stopped moving.
/// These pin down the behaviour that is easy to get subtly wrong - which
/// rows a query matches, and which ages count as stuck for which status.

const _dispatcher = Profile(
  id: 'staff-1',
  email: 'dispatch@example.com',
  fullName: 'Dispatch',
  role: UserRole.superAdmin,
  isActive: true,
);

Delivery _delivery({
  required String id,
  required String code,
  required String name,
  DeliveryStatus status = DeliveryStatus.pending,
  String? phone,
  String dropoff = 'Somewhere in Accra',
  DateTime? createdAt,
  DateTime? assignedAt,
  DateTime? scheduledAt,
}) {
  final at = createdAt ?? DateTime.now();
  return Delivery(
    id: id,
    trackingCode: code,
    status: status,
    customerName: name,
    customerPhone: phone,
    pickupAddress: 'Osu',
    dropoffAddress: dropoff,
    createdAt: at,
    updatedAt: at,
    assignedAt: assignedAt,
    scheduledAt: scheduledAt,
    assignedDriverId: assignedAt == null ? null : 'driver-1',
  );
}

Widget _screen(List<Delivery> deliveries) {
  return ProviderScope(
    overrides: [
      currentProfileProvider.overrideWith((ref) => Stream.value(_dispatcher)),
      recentDeliveriesProvider.overrideWith((ref) => Stream.value(deliveries)),
      driversListProvider.overrideWith((ref) async => <Profile>[]),
      driverRatingSummaryProvider.overrideWith((ref) async => {}),
      poorRatingsProvider.overrideWith((ref) async => []),
    ],
    child: const MaterialApp(home: Scaffold(body: AdminDashboardScreen())),
  );
}

Future<void> _search(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('finds an order by code, name, phone or area', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _screen([
        _delivery(
          id: '1',
          code: 'SD4471',
          name: 'Ama Owusu',
          phone: '+233240000001',
          dropoff: 'East Legon',
        ),
        _delivery(
          id: '2',
          code: 'SD4472',
          name: 'Kojo Mensah',
          phone: '+233240000002',
          dropoff: 'Spintex',
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ama Owusu'), findsOneWidget);
    expect(find.textContaining('Kojo Mensah'), findsOneWidget);

    await _search(tester, 'sd4472');
    expect(find.textContaining('Kojo Mensah'), findsOneWidget);
    expect(find.textContaining('Ama Owusu'), findsNothing);

    await _search(tester, 'ama');
    expect(find.textContaining('Ama Owusu'), findsOneWidget);
    expect(find.textContaining('Kojo Mensah'), findsNothing);

    // A phone number read out over the line arrives in all sorts of
    // shapes, so matching ignores everything that isn't a digit.
    await _search(tester, '024 000 0002');
    expect(find.textContaining('Kojo Mensah'), findsOneWidget);
    expect(find.textContaining('Ama Owusu'), findsNothing);

    await _search(tester, 'legon');
    expect(find.textContaining('Ama Owusu'), findsOneWidget);
    expect(find.textContaining('Kojo Mensah'), findsNothing);
  });

  testWidgets('says nothing matched rather than looking empty', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _screen([_delivery(id: '1', code: 'SD4471', name: 'Ama Owusu')]),
    );
    await tester.pumpAndSettle();

    await _search(tester, 'zzzz');
    expect(find.textContaining('Nothing matches'), findsOneWidget);
    // "No deliveries yet" would be a lie - there is one, just not this one.
    expect(find.text('No deliveries yet'), findsNothing);
  });

  testWidgets('flags work that has stalled, and only that', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    await tester.pumpWidget(
      _screen([
        // Unassigned for two hours: nobody is coming for this on its own.
        _delivery(
          id: 'stale',
          code: 'STALE1',
          name: 'Forgotten Customer',
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
        // Raised a minute ago - not stuck, just new.
        _delivery(id: 'fresh', code: 'FRESH1', name: 'New Customer'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('needs attention'), findsOneWidget);
    expect(find.textContaining('STALE1'), findsWidgets);
  });

  testWidgets('a delivery scheduled for later is waiting, not stuck', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final now = DateTime.now();
    await tester.pumpWidget(
      _screen([
        _delivery(
          id: 'later',
          code: 'LATER1',
          name: 'Tomorrow Customer',
          // Created long ago, but deliberately queued for tomorrow: the
          // whole point of scheduling is that it sits untouched.
          createdAt: now.subtract(const Duration(hours: 5)),
          scheduledAt: now.add(const Duration(hours: 12)),
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('needs attention'), findsNothing);
  });
}
