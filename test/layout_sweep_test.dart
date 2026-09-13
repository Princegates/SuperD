import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/features/admin/providers/admin_providers.dart';
import 'package:superd/features/admin/screens/admin_dashboard_screen.dart';
import 'package:superd/features/admin/screens/drivers_screen.dart';
import 'package:superd/features/admin/screens/home_screen.dart';
import 'package:superd/features/console/screens/console_commission_tab.dart';
import 'package:superd/features/console/screens/console_finance_tab.dart';
import 'package:superd/features/console/screens/console_overview_tab.dart';
import 'package:superd/features/console/screens/console_reports_tab.dart';
import 'package:superd/features/auth/screens/login_screen.dart';
import 'package:superd/features/public/screens/vendor_signup_screen.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/delivery_status.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/user_role.dart';

/// A layout that overflows does not throw in production - it paints a
/// yellow and black stripe over the content and carries on, which is why
/// these went unnoticed until a screenshot arrived. In a test the same
/// condition is an exception, so pumping every screen at the widths people
/// actually hold turns a visual bug into a failing build.
///
/// The widths are real: 320 is a small or split-screen handset, 360 the
/// commonest Android, 412 a large one, 768 a tablet, and 1280/1600 the
/// Console in a browser, which is where dispatch actually works.
/// A double can't key a const map, so these are pairs.
const _widths = <(double, String)>[
  (320, 'small phone'),
  (360, 'phone'),
  (412, 'large phone'),
  (768, 'tablet'),
  (1280, 'laptop'),
  (1600, 'desktop'),
];

final _admin = Profile(
  id: 'staff-1',
  email: 'dispatch@superdeliverygh.com',
  fullName: 'Dispatch',
  role: UserRole.superAdmin,
  isActive: true,
);

/// One rider and one delivery, so screens render their populated state
/// rather than the empty one - an empty list overflows nothing.
final _driver = Profile(
  id: 'driver-1',
  email: 'kofi@example.com',
  fullName: 'Kofi Mensah-Boateng',
  role: UserRole.driver,
  isActive: true,
  phone: '+233240000001',
);

Delivery _delivery() {
  final now = DateTime.now();
  return Delivery(
    id: 'd1',
    trackingCode: 'SD4471',
    status: DeliveryStatus.delivered,
    customerName: 'Ama Owusu',
    customerPhone: '+233240000002',
    pickupAddress: 'The Eagle Enterprise, Osu',
    dropoffAddress:
        '65, Castle Road, Christiansborg, Ringway Estates, La, Accra, '
        'Korle-Klottey Municipal District, Greater Accra Region, Ghana',
    createdAt: now,
    updatedAt: now,
    assignedDriverId: 'driver-1',
    pickedUpAt: now,
    deliveredAt: now,
  );
}

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      currentProfileProvider.overrideWith((ref) => Stream.value(_admin)),
      allDeliveriesProvider.overrideWith((ref) => Stream.value([_delivery()])),
      driversListProvider.overrideWith((ref) async => [_driver]),
      allProfilesProvider.overrideWith((ref) async => [_admin, _driver]),
      driverRatingSummaryProvider.overrideWith((ref) async => {}),
      poorRatingsProvider.overrideWith((ref) async => []),
      zonesProvider.overrideWith((ref) async => []),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Future<void> _sweep(
  WidgetTester tester,
  String name,
  Widget Function() build, {

  /// Some screens animate forever - the sign-in shimmer, for one - so
  /// pumpAndSettle never returns on them. Those get a few fixed frames
  /// instead, which is all a layout check needs.
  bool settles = true,
}) async {
  for (final (width, kind) in _widths) {
    tester.view.physicalSize = Size(width, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(build()));
    if (settles) {
      await tester.pumpAndSettle();
    } else {
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    expect(
      tester.takeException(),
      isNull,
      reason: '$name overflows at ${width.toInt()}dp ($kind)',
    );
  }
}

void main() {
  testWidgets('Dashboard home', (t) async {
    await _sweep(
      t,
      'Home',
      () => HomeScreen(quickLinks: const [], onNavigate: (_) {}),
    );
  });

  testWidgets('Deliveries', (t) async {
    await _sweep(t, 'Deliveries', () => const AdminDashboardScreen());
  });

  testWidgets('Drivers', (t) async {
    await _sweep(t, 'Drivers', () => const DriversScreen());
  });

  testWidgets('Console > Overview', (t) async {
    await _sweep(t, 'Overview', () => const ConsoleOverviewTab());
  });

  testWidgets('Console > Reports', (t) async {
    await _sweep(t, 'Reports', () => const ConsoleReportsTab());
  });

  testWidgets('Console > Finance', (t) async {
    await _sweep(t, 'Finance', () => const ConsoleFinanceTab());
  });

  testWidgets('Console > Commission', (t) async {
    await _sweep(t, 'Commission', () => const ConsoleCommissionTab());
  });

  // The two pages the public actually reaches, and the one every member of
  // staff sees first. All three are served from the web build as well as
  // the app, so the desktop widths matter here more than anywhere.
  testWidgets('Sign in', (t) async {
    await _sweep(t, 'Login', () => const LoginScreen(), settles: false);
  });

  testWidgets('Vendor signup', (t) async {
    await _sweep(t, 'Vendor signup', () => const VendorSignupScreen());
  });
}
