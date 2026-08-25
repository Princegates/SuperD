import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/profile.dart';

final allDeliveriesProvider = StreamProvider<List<Delivery>>((ref) {
  return ref.watch(deliveryRepositoryProvider).watchAllDeliveries();
});

final driversListProvider = FutureProvider<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchDrivers();
});

/// Every user in the system - used by the super-admin Team screen.
final allProfilesProvider = FutureProvider<List<Profile>>((ref) {
  return ref.watch(profileRepositoryProvider).fetchAllProfiles();
});
