import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/profile.dart';
import '../../../models/vendor.dart';
import '../../../models/zone.dart';
import '../../../models/zone_location.dart';

final allDeliveriesProvider = StreamProvider<List<Delivery>>((ref) {
  return ref.watch(deliveryRepositoryProvider).watchAllDeliveries();
});

final driversListProvider = FutureProvider<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchDrivers();
});

/// Every driver's live position, for the Live Map. Kept separate from
/// [driversListProvider] (a one-shot fetch used for rosters/assignment)
/// since this one needs to be a live realtime stream instead.
final driverLocationsProvider = StreamProvider<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).watchDriverLocations();
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
      final deliveries = ref.watch(allDeliveriesProvider).valueOrNull ?? [];

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
