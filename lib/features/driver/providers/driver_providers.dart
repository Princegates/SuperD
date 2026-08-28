import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/driver_daily_fee.dart';

/// Only the deliveries assigned to the signed-in driver. Derives the
/// driver's id from [authStateProvider] (reactive), not just a one-time
/// read of the Supabase client's `currentUser` - the client instance
/// itself never changes, so watching it alone meant this provider was
/// built once and then kept streaming whichever driver was signed in
/// *first*, even after a sign-out/sign-in as a different driver in the
/// same app session. That was letting two different drivers' dashboards
/// show the same underlying stream.
final myDeliveriesProvider = StreamProvider<List<Delivery>>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return Stream.value(const []);
  return ref.watch(deliveryRepositoryProvider).watchDriverDeliveries(userId);
});

/// The signed-in driver's own daily-fee record for today, live - see
/// [DriverDailyFee]. Null means unpaid (no attempt recorded yet, or
/// today's earlier attempt failed).
///
/// Proactively spends a banked free-day credit first (if there is one and
/// today isn't already covered) before starting the live stream - so a
/// driver who earned a reward sees it applied the moment they open the
/// app, not only once dispatch happens to try assigning them something.
/// Harmless (a fast no-op) whenever there's nothing to claim.
final todaysDailyFeeProvider = StreamProvider<DriverDailyFee?>((ref) async* {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) {
    yield null;
    return;
  }
  final repo = ref.watch(driverDailyFeeRepositoryProvider);
  await repo.claimFreeDayIfAvailable(userId);
  yield* repo.watchToday(userId);
});

/// The signed-in driver's own banked free-day balance, live - see
/// `driver_free_day_credits` in `0032_commission_free_days.sql`.
final freeDayBalanceProvider = StreamProvider<int>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return Stream.value(0);
  return ref
      .watch(driverDailyFeeRepositoryProvider)
      .watchFreeDayBalance(userId);
});
