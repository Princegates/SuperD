import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/commission_payment.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/driver_daily_fee.dart';
import '../../../models/driver_notice.dart';
import '../../../models/payment.dart';
import '../../../models/payment_status.dart';
import '../../../models/route_stop.dart';
import '../utils/route_optimizer.dart';

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

/// One sensible visiting order across every pickup/drop-off the signed-in
/// driver currently has outstanding - see `optimizeDriverRoute()` for how
/// the order is worked out. Seeded from the driver's own last-known
/// position (`profiles.last_lat/last_lng`, kept live by the same location
/// stream that feeds the Live Map - see DriverDashboardScreen), so the
/// route re-orders itself as they actually move, not just when a
/// delivery's status changes.
final driverRouteProvider = Provider<List<RouteStop>>((ref) {
  final deliveries = ref.watch(myDeliveriesProvider).valueOrNull ?? const [];
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  return optimizeDriverRoute(
    deliveries,
    startLat: profile?.lastLat,
    startLng: profile?.lastLng,
  );
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
  final commissionEnabled =
      ref.watch(appSettingsProvider).valueOrNull?.driverCommissionEnabled ??
      true;
  if (!commissionEnabled) return 0;
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

/// What the signed-in driver still needs to pay right now toward *today's
/// tier* specifically - 0 once fully waived, or once they've paid up to
/// their current tier. It only ever grows or shrinks to 0, since a lower
/// tier can't reduce what's already been paid today. See
/// [totalCommissionDueProvider] for what [DailyFeeBanner] actually shows/
/// collects - this plus any per-delivery commission still due.
final dailyFeeBalanceProvider = Provider<double>((ref) {
  if (ref.watch(dailyFeeIsWaivedProvider)) return 0;
  final owed = ref.watch(dailyFeeOwedProvider);
  final paid = ref.watch(dailyFeePaidAmountProvider);
  final balance = owed - paid;
  return balance > 0 ? balance : 0;
});

/// The signed-in driver's own still-due per-delivery commission rows,
/// live - see [CommissionRepository.watchDueForDriver]. 0 while the
/// master commission switch is off, mirroring the server-side guard in
/// `driver_commission_due_amount()`.
final myDueCommissionProvider = StreamProvider<List<CommissionPayment>>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return Stream.value(const []);
  return ref.watch(commissionRepositoryProvider).watchDueForDriver(userId);
});

/// The total of [myDueCommissionProvider] - 0 while commission is off.
final commissionDueAmountProvider = Provider<double>((ref) {
  final commissionEnabled =
      ref.watch(appSettingsProvider).valueOrNull?.driverCommissionEnabled ??
      true;
  if (!commissionEnabled) return 0;
  final due = ref.watch(myDueCommissionProvider).valueOrNull ?? const [];
  return due.fold(0.0, (sum, c) => sum + c.amount);
});

/// What [DailyFeeBanner] actually shows and collects: today's tiered-fee
/// balance plus any per-delivery commission still due - one payment
/// (Mobile Money or a manual reference) settles both, see
/// `driver_total_amount_due()` in
/// `0050_bundle_commission_with_daily_fee.sql`. The per-delivery amount
/// stays its own count for reporting (see [myCommissionHistoryProvider]/
/// "My earnings") - this is only the combined figure charged in-app.
final totalCommissionDueProvider = Provider<double>((ref) {
  return ref.watch(dailyFeeBalanceProvider) +
      ref.watch(commissionDueAmountProvider);
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

/// Live payments for every delivery ever assigned to the signed-in
/// driver - the raw data behind their revenue history (today/week/month/
/// year) and the running "today's revenue" figure on their dashboard. See
/// [PaymentRepository.watchMyPayments] for why this needs no driver-id
/// filter (RLS does the scoping).
final myPaymentsProvider = StreamProvider<List<Payment>>((ref) {
  return ref.watch(paymentRepositoryProvider).watchMyPayments();
});

/// How much the signed-in driver has collected *today* across every paid
/// payment on their own deliveries - the live counter shown on their
/// dashboard the moment a customer's payment is marked paid, not just a
/// one-time total. Bucketed by [Payment.paidAt] (falling back to
/// [Payment.createdAt] for a payment marked paid without that timestamp
/// ever being set) rather than the delivery's own date, since a payment
/// can be collected a while after the delivery itself.
final todaysRevenueProvider = Provider<double>((ref) {
  final payments = ref.watch(myPaymentsProvider).valueOrNull ?? const [];
  final now = DateTime.now();
  return payments
      .where((p) => p.status == PaymentStatus.paid)
      .where((p) {
        final when = (p.paidAt ?? p.createdAt).toLocal();
        return when.year == now.year &&
            when.month == now.month &&
            when.day == now.day;
      })
      .fold(0.0, (sum, p) => sum + p.amount);
});

/// The signed-in driver's own per-delivery commission history - every
/// flat fee ever charged to them, whichever status. Needs
/// `0049_driver_commission_history_read.sql`'s driver-self-read RLS
/// policy; comes back empty for a driver on any earlier migration.
final myCommissionHistoryProvider = FutureProvider<List<CommissionPayment>>((
  ref,
) async {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return const [];
  return ref.watch(commissionRepositoryProvider).fetchForDriver(userId);
});

/// The signed-in driver's own daily-fee history - every day they've
/// attempted or completed payment for, not just today (see
/// [todaysDailyFeeRecordsProvider] for that).
final myDailyFeeHistoryProvider = FutureProvider<List<DriverDailyFee>>((
  ref,
) async {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return const [];
  return ref
      .watch(driverDailyFeeRepositoryProvider)
      .fetchHistoryForDriver(userId);
});

/// Every notice currently visible to the signed-in driver - broadcasts
/// (promotions, platform-wide heads-up) and their own direct messages -
/// with anything they've already closed filtered out. RLS already limits
/// the underlying stream to active/unexpired/broadcast-or-theirs rows
/// (see [DriverNoticeRepository.watchVisibleNotices]); this just adds the
/// per-driver dismissal filter, newest first.
final myVisibleNoticesProvider = StreamProvider<List<DriverNotice>>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return Stream.value(const []);
  return ref
      .watch(driverNoticeRepositoryProvider)
      .watchVisibleNotices()
      .map(
        (notices) => notices.where((n) => !n.isDismissedBy(userId)).toList(),
      );
});
