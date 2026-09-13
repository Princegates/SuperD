import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/features/admin/providers/admin_providers.dart';
import 'package:superd/features/console/screens/console_overview_tab.dart';
import 'package:superd/features/console/screens/console_reports_tab.dart';
import 'package:superd/models/delivery.dart';
import 'package:superd/models/profile.dart';
import 'package:superd/models/user_role.dart';

/// Console > Overview and Console > Reports carried the same hardcoded
/// tile width as the dashboard did, so both were a single column of
/// figures on a phone. These pin that they are not, at the width a
/// dispatcher actually holds.

const _admin = Profile(
  id: 'staff-1',
  email: 'dispatch@superdeliverygh.com',
  fullName: 'Dispatch',
  role: UserRole.superAdmin,
  isActive: true,
);

Widget _host(Widget child) {
  return ProviderScope(
    overrides: [
      currentProfileProvider.overrideWith((ref) => Stream.value(_admin)),
      allDeliveriesProvider.overrideWith((ref) => Stream.value(<Delivery>[])),
      driversListProvider.overrideWith((ref) async => <Profile>[]),
      allProfilesProvider.overrideWith((ref) async => <Profile>[]),
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

Future<void> _pumpAt(WidgetTester tester, Widget child, double width) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_host(child));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Overview puts two tiles to a row on a phone', (tester) async {
    await _pumpAt(tester, const ConsoleOverviewTab(), 360);

    final first = tester.getTopLeft(find.text('Total deliveries'));
    final second = tester.getTopLeft(find.text('Completed'));

    expect(second.dy, first.dy, reason: 'the first two should share a row');
    expect(second.dx, greaterThan(first.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Reports puts two tiles to a row on a phone', (tester) async {
    await _pumpAt(tester, const ConsoleReportsTab(), 360);

    final first = tester.getTopLeft(find.text('Deliveries'));
    final second = tester.getTopLeft(find.text('Delivered'));

    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('neither overflows at 320dp', (tester) async {
    await _pumpAt(tester, const ConsoleOverviewTab(), 320);
    expect(tester.takeException(), isNull);

    await _pumpAt(tester, const ConsoleReportsTab(), 320);
    expect(tester.takeException(), isNull);
  });
}
