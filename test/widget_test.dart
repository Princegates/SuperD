import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:superd/app.dart';

void main() {
  testWidgets('shows the missing-config screen when no env.json is supplied',
      (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SuperDApp()));

    expect(find.text('SuperD is not configured yet'), findsOneWidget);
  });
}
