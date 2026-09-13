import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/shared/widgets/location_field.dart';

/// The two public forms both ask "where?" through [LocationField]. These
/// pin down the part that has to hold up in front of a stranger on a
/// phone: all three ways of answering are offered, they survive a narrow
/// screen, and a refused location prompt says so instead of leaving a
/// dead button.

/// Geolocator has no implementation under `flutter test`; stand in for its
/// channel so permission handling can be driven from here.
void _stubGeolocator({required String permission}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('flutter.baseflow.com/geolocator'),
        (call) async => switch (call.method) {
          // 0 = denied, 1 = deniedForever, 3 = whileInUse
          'checkPermission' || 'requestPermission' => switch (permission) {
            'denied' => 0,
            'deniedForever' => 1,
            _ => 3,
          },
          'isLocationServiceEnabled' => true,
          _ => null,
        },
      );
}

Widget _host({required TextEditingController controller, bool hasLocation = false}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: LocationField(
          controller: controller,
          label: 'Delivery address',
          mapTitle: 'Where should it be delivered?',
          helperText: "Can't name the street? Drop a pin instead",
          hasLocation: hasLocation,
          confirmedHint: 'Got it - your price is below',
          onPicked: (_, _) {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('offers typing, current location and the map, without overflow', (
    tester,
  ) async {
    _stubGeolocator(permission: 'whileInUse');
    // Narrow: the width where two side-by-side buttons would collide.
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(controller: TextEditingController()));
    await tester.pumpAndSettle();

    expect(find.text('Delivery address'), findsOneWidget);
    expect(find.text('Use my location'), findsOneWidget);
    expect(find.text('Pin on map'), findsOneWidget);
  });

  testWidgets('confirms once a coordinate is held', (tester) async {
    _stubGeolocator(permission: 'whileInUse');
    await tester.pumpWidget(
      _host(controller: TextEditingController(), hasLocation: true),
    );
    await tester.pumpAndSettle();

    expect(find.text('Got it - your price is below'), findsOneWidget);
  });

  testWidgets('a refused prompt explains itself rather than doing nothing', (
    tester,
  ) async {
    _stubGeolocator(permission: 'denied');
    await tester.pumpWidget(_host(controller: TextEditingController()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Location permission was declined'),
      findsOneWidget,
    );
  });

  testWidgets('a permanently blocked prompt points at settings', (
    tester,
  ) async {
    _stubGeolocator(permission: 'deniedForever');
    await tester.pumpWidget(_host(controller: TextEditingController()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Use my location'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Location is blocked'), findsOneWidget);
  });
}
