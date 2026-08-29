import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/vehicle_type.dart';
import '../../../models/vendor.dart';

/// Public vendor lookup by their link code - powers the customer request
/// form's "Ordering from {vendor_name}" header. No session required.
final vendorByCodeProvider = FutureProvider.family<VendorPublicInfo?, String>((
  ref,
  code,
) {
  return ref.watch(vendorRepositoryProvider).fetchVendorByCode(code);
});

/// Every configured vehicle type - powers the customer request form's
/// vehicle picker, defaulting to whichever one has [VehicleType.isDefault]
/// set (motorcycle out of the box). No session required - see
/// [VehicleTypeRepository.fetchAllPublic].
final publicVehicleTypesProvider = FutureProvider<List<VehicleType>>((ref) {
  return ref.watch(vehicleTypeRepositoryProvider).fetchAllPublic();
});

/// A vendor's own order history, keyed by their PRIVATE `ordersCode` (not
/// the public code customers get) - powers the vendor's own orders page at
/// `/vendor-orders/:ordersCode`, live (polled every 5s - see
/// `watchVendorDeliveries`) so a status change shows up without a manual
/// refresh. No session required, but the ordersCode itself is the secret
/// that keeps this scoped to just this vendor.
final vendorDeliveriesProvider =
    StreamProvider.family<List<VendorDelivery>, String>((ref, ordersCode) {
      return ref
          .watch(vendorRepositoryProvider)
          .watchVendorDeliveries(ordersCode);
    });

/// A single delivery, keyed by the tracking code a customer was given when
/// they submitted it - powers their own "Track this order" page at
/// `/t/:trackingCode`. Never exposes any other delivery, even another one
/// from the same vendor - see `get_delivery_by_tracking_code()`.
final trackedDeliveryProvider = StreamProvider.family<VendorDelivery?, String>((
  ref,
  trackingCode,
) {
  return ref
      .watch(vendorRepositoryProvider)
      .watchDeliveryByTrackingCode(trackingCode);
});
