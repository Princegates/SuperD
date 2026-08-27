import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Drivers ordered best-suited-first for a delivery in [targetZoneId]:
/// same-zone drivers before everyone else, and within each group whoever
/// currently has the fewest active jobs first. No external AI call - this
/// is a plain, free, instant calculation, which is what "suggest the best
/// rider" actually reduces to here (zone match + current workload).
///
/// Only active drivers are considered - a self-signed-up driver pending
/// approval (or one a dispatcher has deactivated) can't be assigned work.
final rankedDriversProvider = Provider.family<List<Profile>, String?>((
  ref,
  targetZoneId,
) {
  final drivers = (ref.watch(driversListProvider).valueOrNull ?? [])
      .where((d) => d.isActive)
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

  final ranked = [...drivers];
  ranked.sort((a, b) {
    final aInZone = targetZoneId != null && a.zoneId == targetZoneId;
    final bInZone = targetZoneId != null && b.zoneId == targetZoneId;
    if (aInZone != bInZone) return aInZone ? -1 : 1;

    final aCount = activeCounts[a.id] ?? 0;
    final bCount = activeCounts[b.id] ?? 0;
    if (aCount != bCount) return aCount.compareTo(bCount);

    return a.displayName.compareTo(b.displayName);
  });
  return ranked;
});
