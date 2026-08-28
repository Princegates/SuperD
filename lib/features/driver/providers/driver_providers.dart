import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
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

/// How many deliveries the signed-in driver has completed *today* - the
/// count that picks their daily-fee tier. Derived from
/// [myDeliveriesProvider] (already live) instead of a separate query, so
/// it updates the instant a delivery is marked delivered.
final todaysDeliveredCountProvider = Provider<int>((ref) {
  final deliveries = ref.watch(myDeliveriesProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return deliveries.where((d) {
    final deliveredAt = d.deliveredAt?.toLocal();
    return d.status == DeliveryStatus.delivered &&
        deliveredAt != null &&
        deliveredAt.year == now.year &&
        deliveredAt.month == now.month &&
        deliveredAt.day == now.day;
  }).length;
});

/// The tier amount the signed-in driver owes for today, right now - the
/// highest tier whose threshold [todaysDeliveredCountProvider] has
/// reached. Live as either the tier list or the delivered count changes -
/// the same live re-evaluation the database itself enforces (see
/// `driver_daily_fee_amount()`), just computed client-side for a snappy
/// display; the actual amount charged always comes from that same
/// database function, never trusted from here.
final dailyFeeOwedProvider = Provider<double>((ref) {
  final tiers = ref.watch(dailyFeeTiersProvider).valueOrNull ?? const [];
  final count = ref.watch(todaysDeliveredCountProvider);
  var owed = 0.0;
  for (final tier in tiers) {
    if (tier.minDeliveries > count) break;
    owed = tier.amount;
  }
  return owed;
});

/// The signed-in driver's own daily-fee payment/waiver rows for today,
/// live - see [DriverDailyFee]. Possibly more than one now: crossing into
/// a higher tier mid-day means a second payment. Empty means nothing
/// attempted yet today.
///
/// Proactively spends a banked free-day credit first (if there is one and
/// today isn't already covered) before starting the live stream - so a
/// driver who earned a reward sees it applied the moment they open the
/// app, not only once dispatch happens to try assigning them something.
/// Harmless (a fast no-op) whenever there's nothing to claim.
final todaysDailyFeeRecordsProvider = StreamProvider<List<DriverDailyFee>>((
  ref,
) async* {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) {
    yield const [];
    return;
  }
  final repo = ref.watch(driverDailyFeeRepositoryProvider);
  await repo.claimFreeDayIfAvailable(userId);
  yield* repo.watchTodayRecords(userId);
});

/// Total the signed-in driver has already paid or been waived today -
/// across every row, since a top-up after crossing a tier lands as a
/// second one.
final dailyFeePaidAmountProvider = Provider<double>((ref) {
  final records =
      ref.watch(todaysDailyFeeRecordsProvider).valueOrNull ?? const [];
  return records
      .where((r) => r.isCleared)
      .fold(0.0, (sum, r) => sum + r.amount);
});

/// Whether a dispatcher/super admin has waived the whole day for the
/// signed-in driver - clears the balance regardless of tier.
final dailyFeeIsWaivedProvider = Provider<bool>((ref) {
  final records =
      ref.watch(todaysDailyFeeRecordsProvider).valueOrNull ?? const [];
  return records.any((r) => r.status == DailyFeeStatus.waived);
});

/// What the signed-in driver still needs to pay right now - 0 once fully
/// waived, or once they've paid up to their current tier. This is the
/// amount [DailyFeeBanner] shows and offers to collect; it only ever
/// grows or shrinks to 0, since a lower tier can't reduce what's already
/// been paid today.
final dailyFeeBalanceProvider = Provider<double>((ref) {
  if (ref.watch(dailyFeeIsWaivedProvider)) return 0;
  final owed = ref.watch(dailyFeeOwedProvider);
  final paid = ref.watch(dailyFeePaidAmountProvider);
  final balance = owed - paid;
  return balance > 0 ? balance : 0;
});

/// The most recent pending/failed payment attempt today, if any - drives
/// [DailyFeeBanner]'s status message ("payment pending" vs "try again").
final dailyFeeLatestAttemptProvider = Provider<DriverDailyFee?>((ref) {
  final records =
      ref.watch(todaysDailyFeeRecordsProvider).valueOrNull ?? const [];
  final attempts =
      records
          .where(
            (r) =>
                r.status == DailyFeeStatus.pending ||
                r.status == DailyFeeStatus.failed,
          )
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return attempts.isEmpty ? null : attempts.first;
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
