import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/app.dart';
import 'package:superd/core/app_identity.dart';

void main() {
  testWidgets('shows the missing-config screen when no env.json is supplied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: SuperDApp()));

    // Interpolated rather than spelled out, so renaming the product does
    // not leave this test asserting a name the app no longer uses - which
    // is exactly what it did on the way from SuperD to SuperDelivery.
    expect(find.text('$kAppName is not configured yet'), findsOneWidget);
  });
}
