import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:superd/core/providers/core_providers.dart';
import 'package:superd/data/repositories/driver_daily_fee_repository.dart';
import 'package:superd/data/repositories/settings_repository.dart';
import 'package:superd/data/repositories/vehicle_type_repository.dart';
import 'package:superd/features/console/screens/console_settings_tab.dart';
import 'package:superd/models/app_settings.dart';
import 'package:superd/models/driver_daily_fee_tier.dart';
import 'package:superd/models/vehicle_type.dart';

/// Records what was asked of it instead of touching the network, so the
/// currency dropdown's behavior can be tested without a live Supabase
/// project.
class _FakeSettingsRepository extends SettingsRepository {
  _FakeSettingsRepository() : super(_testClient());

  String? lastCurrency;
  String? lastTheme;
  bool? lastAllowDriverWebLogin;
  double? lastBaseFare;
  double? lastPricePerKm;

  @override
  Stream<AppSettings> watchSettings() => Stream.value(
    const AppSettings(
      currency: 'GHS',
      theme: 'navy_gold',
      allowDriverWebLogin: false,
      baseFare: 5,
      pricePerKm: 1.5,
    ),
  );

  @override
  Future<void> updateCurrency(String currency) async {
    lastCurrency = currency;
  }

  @override
  Future<void> updateTheme(String themeKey) async {
    lastTheme = themeKey;
  }

  @override
  Future<void> setAllowDriverWebLogin(bool allow) async {
    lastAllowDriverWebLogin = allow;
  }

  @override
  Future<void> updatePricing({
    required double baseFare,
    required double pricePerKm,
  }) async {
    lastBaseFare = baseFare;
    lastPricePerKm = pricePerKm;
  }

  double? lastCommissionFlatFee;

  @override
  Future<void> updateCommissionFlatFee(double flatFee) async {
    lastCommissionFlatFee = flatFee;
  }

  int? lastFreeDayThreshold;

  @override
  Future<void> updateFreeDayThreshold(int? threshold) async {
    lastFreeDayThreshold = threshold;
  }

  int? lastZoneAutoAssignCap;

  @override
  Future<void> updateZoneAutoAssignCap(int cap) async {
    lastZoneAutoAssignCap = cap;
  }

  String? lastSupportPhone;

  @override
  Future<void> updateSupportPhone(String? phone) async {
    lastSupportPhone = phone;
  }

  String? lastAdminAlertEmail;

  @override
  Future<void> updateAdminAlertEmail(String? email) async {
    lastAdminAlertEmail = email;
  }

  String? lastAdminAlertPhone;

  @override
  Future<void> updateAdminAlertPhone(String? phone) async {
    lastAdminAlertPhone = phone;
  }
}

/// Records tier add/edit/remove calls instead of touching the network -
/// same purpose as [_FakeSettingsRepository].
class _FakeDriverDailyFeeRepository extends DriverDailyFeeRepository {
  _FakeDriverDailyFeeRepository() : super(_testClient());

  @override
  Stream<List<DriverDailyFeeTier>> watchTiers() => Stream.value(const []);

  DriverDailyFeeTier? lastAdded;

  @override
  Future<void> addTier({
    required int minDeliveries,
    required double amount,
  }) async {
    lastAdded = DriverDailyFeeTier(
      id: 'fake',
      minDeliveries: minDeliveries,
      amount: amount,
    );
  }
}

/// Records vehicle-type add/edit/remove/default calls instead of touching
/// the network - same purpose as [_FakeDriverDailyFeeRepository].
class _FakeVehicleTypeRepository extends VehicleTypeRepository {
  _FakeVehicleTypeRepository() : super(_testClient());

  @override
  Stream<List<VehicleType>> watchAll() => Stream.value(const []);
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
          driverDailyFeeRepositoryProvider.overrideWithValue(
            _FakeDriverDailyFeeRepository(),
          ),
          vehicleTypeRepositoryProvider.overrideWithValue(
            _FakeVehicleTypeRepository(),
          ),
          supabaseClientProvider.overrideWithValue(_testClient()),
        ],
        child: const MaterialApp(home: Scaffold(body: ConsoleSettingsTab())),
      ),
    );
    await tester.pumpAndSettle();

    // The dropdown starts on whatever appSettingsProvider reports. The
    // internal-alerts card above it can push it out of the initial
    // viewport, so scroll to it before asserting/tapping.
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
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
          driverDailyFeeRepositoryProvider.overrideWithValue(
            _FakeDriverDailyFeeRepository(),
          ),
          vehicleTypeRepositoryProvider.overrideWithValue(
            _FakeVehicleTypeRepository(),
          ),
          supabaseClientProvider.overrideWithValue(_testClient()),
        ],
        child: const MaterialApp(home: Scaffold(body: ConsoleSettingsTab())),
      ),
    );
    await tester.pumpAndSettle();

    // All 6 presets show up as swatches, including the current one. The
    // cards above them (support phone, internal alerts) push them well
    // past the ListView's initial render/cache extent, so - unlike a
    // widget merely off-screen but still mounted - it doesn't exist in
    // the tree yet for a plain ensureVisible to find; drag repeatedly
    // until it's actually built.
    await tester.dragUntilVisible(
      find.text('Ocean Blue'),
      find.byType(Scrollable).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    expect(find.text('Navy & Gold'), findsOneWidget);
    expect(find.text('Ocean Blue'), findsOneWidget);
    expect(find.text('Charcoal'), findsOneWidget);

    await tester.tap(find.text('Ocean Blue'));
    await tester.pumpAndSettle();

    expect(fakeRepo.lastTheme, 'ocean_blue');
  });

  testWidgets('lets a super admin toggle driver web login', (tester) async {
    final fakeRepo = _FakeSettingsRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(fakeRepo),
          driverDailyFeeRepositoryProvider.overrideWithValue(
            _FakeDriverDailyFeeRepository(),
          ),
          vehicleTypeRepositoryProvider.overrideWithValue(
            _FakeVehicleTypeRepository(),
          ),
          supabaseClientProvider.overrideWithValue(_testClient()),
        ],
        child: const MaterialApp(home: Scaffold(body: ConsoleSettingsTab())),
      ),
    );
    await tester.pumpAndSettle();

    // The driver-web-login switch sits well below the new pricing/
    // commission cards, so it may start outside the ListView's viewport -
    // and there's now a second Switch ("Driver commission") above it, so
    // scroll to and target this one specifically by its own label rather
    // than by type alone.
    final webLoginLabel = find.text('Allow driver sign-in on the web');
    await tester.scrollUntilVisible(
      webLoginLabel,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    final webLoginSwitch = find.descendant(
      of: find.ancestor(of: webLoginLabel, matching: find.byType(Card)),
      matching: find.byType(Switch),
    );

    expect(webLoginSwitch, findsOneWidget);
    expect(tester.widget<Switch>(webLoginSwitch).value, false);

    await tester.tap(webLoginSwitch);
    await tester.pumpAndSettle();

    expect(fakeRepo.lastAllowDriverWebLogin, true);
  });
}
