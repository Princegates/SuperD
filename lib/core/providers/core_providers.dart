import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/audit_repository.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/commission_repository.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../data/repositories/driver_daily_fee_repository.dart';
import '../../data/repositories/driver_notice_repository.dart';
import '../../data/repositories/payment_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/vehicle_type_repository.dart';
import '../../data/repositories/vendor_repository.dart';
import '../../models/app_settings.dart';
import '../../models/driver_daily_fee_tier.dart';
import '../../models/profile.dart';
import '../../models/vehicle_type.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  return DeliveryRepository(ref.watch(supabaseClientProvider));
});

final paymentRepositoryProvider = Provider<PaymentRepository>((ref) {
  return PaymentRepository(ref.watch(supabaseClientProvider));
});

final vendorRepositoryProvider = Provider<VendorRepository>((ref) {
  return VendorRepository(ref.watch(supabaseClientProvider));
});

final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(ref.watch(supabaseClientProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository(ref.watch(supabaseClientProvider));
});

final commissionRepositoryProvider = Provider<CommissionRepository>((ref) {
  return CommissionRepository(ref.watch(supabaseClientProvider));
});

final driverDailyFeeRepositoryProvider = Provider<DriverDailyFeeRepository>((
  ref,
) {
  return DriverDailyFeeRepository(ref.watch(supabaseClientProvider));
});

final driverNoticeRepositoryProvider = Provider<DriverNoticeRepository>((ref) {
  return DriverNoticeRepository(ref.watch(supabaseClientProvider));
});

final vehicleTypeRepositoryProvider = Provider<VehicleTypeRepository>((ref) {
  return VehicleTypeRepository(ref.watch(supabaseClientProvider));
});

/// The app-wide settings row (currently just the currency), kept live so a
/// super admin's change in Console > Settings is picked up everywhere else
/// without a restart.
final appSettingsProvider = StreamProvider<AppSettings>((ref) {
  return ref.watch(settingsRepositoryProvider).watchSettings();
});

/// Fires whenever the Supabase auth session changes (sign in / out / token
/// refresh). Everything else in the app that cares about "who is logged in"
/// derives from this.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

/// Whether a driver may sign in on the web dashboard right now - a plain,
/// one-time fetch (re-run on every sign-in/out via the authState watch
/// below), deliberately not the live [appSettingsProvider] stream. This
/// gates a real redirect decision in the router, and a realtime channel
/// that's briefly slow to connect or times out - which does happen in
/// practice - shouldn't be able to make that decision hang or default to
/// "denied" just because the WebSocket isn't cooperating yet.
final driverWebLoginAllowedProvider = FutureProvider<bool>((ref) async {
  ref.watch(authStateProvider);
  final settings = await ref.watch(settingsRepositoryProvider).fetchSettings();
  return settings.allowDriverWebLogin;
});

/// Set briefly by the router when it force-signs-out a driver account that
/// tried to sign in on the web build (this dashboard is back-office only -
/// drivers use the mobile app). The login screen watches this to show a
/// one-time explanation, then resets it.
final driverWebBlockedProvider = StateProvider<bool>((ref) => false);

/// Every configured driver daily-fee tier, live, sorted ascending by
/// [DriverDailyFeeTier.minDeliveries] - empty means the whole feature is
/// off. Shared between the driver dashboard (to work out what today's fee
/// is) and Console > Settings/Daily Fees (to manage and enforce the tier
/// list) - see `driver_daily_fee_tiers` in `0037_tiered_daily_fee.sql`.
final dailyFeeTiersProvider = StreamProvider<List<DriverDailyFeeTier>>((ref) {
  return ref
      .watch(driverDailyFeeRepositoryProvider)
      .watchTiers()
      .map(
        (tiers) =>
            [...tiers]
              ..sort((a, b) => a.minDeliveries.compareTo(b.minDeliveries)),
      );
});

/// Every configured vehicle type, live, sorted by surcharge ascending -
/// powers Console > Settings' editor. See `vehicle_types` in
/// `0051_vehicle_types.sql`; the customer request form uses
/// [VehicleTypeRepository.fetchAllPublic] instead (no session to read
/// this live stream with).
final vehicleTypesProvider = StreamProvider<List<VehicleType>>((ref) {
  return ref
      .watch(vehicleTypeRepositoryProvider)
      .watchAll()
      .map(
        (types) => [...types]..sort((a, b) => a.extraFee.compareTo(b.extraFee)),
      );
});

/// The signed-in user's app profile (role, name, ...), kept live so a role
/// change by an admin is picked up without a restart.
final currentProfileProvider = StreamProvider<Profile?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;

  if (userId == null) {
    return Stream.value(null);
  }
  return ref.watch(profileRepositoryProvider).watchProfile(userId);
});
