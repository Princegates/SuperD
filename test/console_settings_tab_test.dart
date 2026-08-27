import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/data/repositories/settings_repository.dart';
import 'package:superd/features/console/screens/console_settings_tab.dart';
import 'package:superd/models/app_settings.dart';

/// Records what was asked of it instead of touching the network, so the
/// currency dropdown's behavior can be tested without a live Supabase
/// project.
class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository() : super(_testClient());

  String? lastCurrency;
  String? lastTheme;

  @override
  Stream<AppSettings> watchSettings() =>
      Stream.value(const AppSettings(currency: 'GHS', theme: 'navy_gold'));

  @override
  Future<void> updateCurrency(String currency) async {
    lastCurrency = currency;
  }

  @override
  Future<void> updateTheme(String themeKey) async {
    lastTheme = themeKey;
  }
}

/// A `SupabaseClient` with token auto-refresh disabled, so it doesn't leave
/// a background timer running past the end of the test.
SupabaseClient _testClient() => SupabaseClient(
  'https://x.test',
  'anon',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
);

void main() {
  testWidgets('shows the current currency and lets a super admin change it', (
    tester,
  ) async {
    final fakeRepo = _FakeSettingsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(fakeRepo),
          supabaseClientProvider.overrideWithValue(_testClient()),
        ],
        child: const MaterialApp(home: Scaffold(body: ConsoleSettingsTab())),
      ),
    );
    await tester.pumpAndSettle();

    // The dropdown starts on whatever appSettingsProvider reports.
    expect(find.text('Ghana Cedi (GHS)'), findsOneWidget);

    // Open the dropdown and pick a different currency.
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nigerian Naira (NGN)').last);
    await tester.pumpAndSettle();

    expect(fakeRepo.lastCurrency, 'NGN');
  });

  testWidgets('lets a super admin pick a different theme', (tester) async {
    final fakeRepo = _FakeSettingsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(fakeRepo),
          supabaseClientProvider.overrideWithValue(_testClient()),
        ],
        child: const MaterialApp(home: Scaffold(body: ConsoleSettingsTab())),
      ),
    );
    await tester.pumpAndSettle();

    // All 6 presets show up as swatches, including the current one.
    expect(find.text('Navy & Gold'), findsOneWidget);
    expect(find.text('Ocean Blue'), findsOneWidget);
    expect(find.text('Charcoal'), findsOneWidget);

    await tester.tap(find.text('Ocean Blue'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastTheme, 'ocean_blue');
  });
}
