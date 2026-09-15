import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_rating.dart';
import '../../../models/delivery_status.dart';
import '../../../models/profile.dart';
import '../../../models/vendor.dart';
import '../../../models/zone.dart';
import '../../../models/zone_location.dart';

/// Recent deliveries, live - the operational feed. Everything dispatch
/// does today reads this: the Deliveries screen, the dashboard tiles, the
/// Drivers screen's active counts, the shell's new-order notification.
///
/// Deliberately not named "all": it covers
/// [DeliveryRepository.recentWindow], and a provider that claimed
/// otherwise would be a quiet lie to every screen reading it. For the
/// whole history, see [deliveryHistoryProvider].
final recentDeliveriesProvider = StreamProvider<List<Delivery>>((ref) {
  return ref.watch(deliveryRepositoryProvider).watchRecentDeliveries();
});

/// Every delivery ever - what reporting reads.
///
/// A fetch rather than a subscription, and autoDispose so it is released
/// when the reader closes the report. Console Reports offers a range going
/// back five years and defaults to all of it, and a vendor's page shows
/// lifetime totals, so these genuinely need the whole table - but only
/// while someone is looking at them, which is the difference that matters.
final deliveryHistoryProvider = FutureProvider.autoDispose<List<Delivery>>((
  ref,
) {
  return ref.watch(deliveryRepositoryProvider).fetchAllDeliveries();
});

final driversListProvider = FutureProvider<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchDrivers();
});

/// What customers think of each driver, keyed by driver id.
///
/// Customers have been rating drivers since 0034 and nothing has ever
/// read it back. Empty for a driver calling this themselves - the RLS
/// policy on delivery_ratings only admits a dispatcher or above.
final driverRatingSummaryProvider =
    FutureProvider<Map<String, DriverRatingSummary>>((ref) {
      return ref.watch(ratingRepositoryProvider).fetchSummary();
    });

/// Recent ratings of three or below, newest first - the ones that
/// describe a problem rather than confirm things went fine.
final poorRatingsProvider = FutureProvider<List<DeliveryRating>>((ref) {
  return ref.watch(ratingRepositoryProvider).fetchRecent(onlyPoor: true);
});

/// How often the Live Map asks where everyone is. Matched to the rate
/// riders actually report at (DriverDashboardScreen's 15s interval) -
/// polling faster would just re-read unchanged rows.
///
/// A provider rather than a constant so a test can wind it down instead
/// of sleeping through real seconds; nothing in the app overrides it.
final liveMapPollIntervalProvider = Provider<Duration>(
  (ref) => const Duration(seconds: 15),
);

/// Drivers currently sharing a position, for the Live Map.
///
/// Polled, not subscribed - see
/// [ProfileRepository.fetchLiveDriverLocations] for why. autoDispose
/// matters as much as the polling does: the old realtime subscription
/// stayed open for the life of the session whether or not anyone had the
/// map on screen, and this stops the moment the last viewer leaves.
///
/// Kept separate from [driversListProvider] (the roster) because they
/// answer different questions and change at wildly different rates.
final driverLocationsProvider =
    StreamProvider.autoDispose<List<Profile>>((ref) async* {
      final repo = ref.watch(profileRepositoryProvider);
      final interval = ref.watch(liveMapPollIntervalProvider);
      var running = true;
      ref.onDispose(() => running = false);
      while (running) {
        yield await repo.fetchLiveDriverLocations();
        if (!running) break;
        await Future<void>.delayed(interval);
      }
    });

/// Every user in the system - used by the super-admin Team screen.
final allProfilesProvider = FutureProvider<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchAllProfiles();
});

final zonesProvider = FutureProvider<List<Zone>>((ref) {
  return ref.watch(vendorRepositoryProvider).fetchZones();
});

final vendorsProvider = FutureProvider<List<Vendor>>((ref) {
  return ref.watch(vendorRepositoryProvider).fetchVendors();
});

/// Every vendor, live - just for the admin shell's "new vendor registered"
/// in-app notification. Kept separate from [vendorsProvider] (a one-shot
/// fetch with the zone-name join the Vendors screen needs) for the same
/// reason [driverLocationsProvider] is separate from [driversListProvider].
final vendorRegistrationsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(vendorRepositoryProvider).watchVendorRegistrations();
});

/// The named places within one zone - see the Console's Zones tab.
final zoneLocationsProvider = FutureProvider.family<List<ZoneLocation>, String>(
  (ref, zoneId) {
    return ref.watch(vendorRepositoryProvider).fetchZoneLocations(zoneId);
  },
);

/// Drivers who still owe today's daily fee - empty whenever that feature
/// is off. Used by [rankedDriversProvider] to keep the dispatcher's
/// manual-assignment picker from offering a driver the database would
/// reject anyway (see `0031_driver_daily_fee.sql`).
final unpaidDriverIdsTodayProvider = FutureProvider<Set<String>>((ref) {
  return ref
      .watch(driverDailyFeeRepositoryProvider)
      .fetchUnpaidDriverIdsToday();
});

/// Drivers ordered best-suited-first for a delivery picked up at
/// [pickup] - same idea, same 15-minute staleness cutoff
/// ([Profile.hasRecentLocation]), as the automatic assignment algorithm
/// itself (see `0044_proximity_based_auto_assignment.sql`): whoever has
/// a recent live location and is physically closest to that point ranks
/// first; drivers with no current position trail behind everyone who
/// has one. Within each of those two groups, whoever currently has the
/// fewest active jobs comes first. No external AI call - this is a
/// plain, free, instant calculation.
///
/// Only active, unfrozen, paid-up drivers are considered - a self-signed-up
/// driver pending approval (or one a dispatcher has deactivated) can't be
/// assigned work, neither can one a super admin has frozen (e.g. for
/// unpaid commission) - see `is_frozen` in
/// `0025_driver_categories_and_status.sql` - nor one who owes today's
/// daily fee.
final rankedDriversProvider =
    Provider.family<List<Profile>, ({double? pickupLat, double? pickupLng})>((
      ref,
      pickup,
    ) {
      final unpaidIds =
          ref.watch(unpaidDriverIdsTodayProvider).valueOrNull ?? {};
      final drivers = (ref.watch(driversListProvider).valueOrNull ?? [])
          .where((d) => d.isActive && !d.isFrozen && !unpaidIds.contains(d.id))
          .toList();
      final deliveries = ref.watch(recentDeliveriesProvider).valueOrNull ?? [];

      final activeCounts = <String, int>{};
      for (final delivery in deliveries) {
        final driverId = delivery.assignedDriverId;
        if (driverId == null) continue;
        if (delivery.status == DeliveryStatus.delivered ||
            delivery.status == DeliveryStatus.cancelled) {
          continue;
        }
        activeCounts.update(driverId, (count) => count + 1, ifAbsent: () => 1);
      }

      const distanceCalc = Distance();
      double? distanceKmTo(Profile driver) {
        final pickupLat = pickup.pickupLat;
        final pickupLng = pickup.pickupLng;
        if (pickupLat == null || pickupLng == null) return null;
        if (!driver.hasRecentLocation) return null;
        return distanceCalc.as(
          LengthUnit.Kilometer,
          LatLng(pickupLat, pickupLng),
          LatLng(driver.lastLat!, driver.lastLng!),
        );
      }

      final ranked = [...drivers];
      ranked.sort((a, b) {
        final aDist = distanceKmTo(a);
        final bDist = distanceKmTo(b);
        if ((aDist == null) != (bDist == null)) {
          return aDist == null ? 1 : -1;
        }
        if (aDist != null && bDist != null && aDist != bDist) {
          return aDist.compareTo(bDist);
        }

        final aCount = activeCounts[a.id] ?? 0;
        final bCount = activeCounts[b.id] ?? 0;
        if (aCount != bCount) return aCount.compareTo(bCount);

        return a.displayName.compareTo(b.displayName);
      });
      return ranked;
    });

/// Signed links to every rider's photograph, in one request rather than
/// one per row.
///
/// Keyed by `avatar_path`, so a caller looks up `photos[driver.avatarPath]`
/// and gets null for anyone without a photo - which is most riders to
/// begin with, and renders as initials. Signed URLs expire; this rebuilds
/// with the roster it belongs to.
final driverPhotoUrlsProvider = FutureProvider<Map<String, String>>((
  ref,
) async {
  final drivers = await ref.watch(driversListProvider.future);
  final paths = [for (final d in drivers) ?d.avatarPath];
  return ref.watch(profileRepositoryProvider).riderPhotoUrls(paths);
});
