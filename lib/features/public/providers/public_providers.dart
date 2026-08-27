import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/vendor.dart';

/// Public vendor lookup by their link code - powers the customer request
/// form's "Ordering from {vendor_name}" header. No session required.
final vendorByCodeProvider = FutureProvider.family<VendorPublicInfo?, String>((
  ref,
  code,
) {
  return ref.watch(vendorRepositoryProvider).fetchVendorByCode(code);
});

/// A vendor's own order history, keyed by their link code - powers the
/// order-tracking page at `/v/:code/orders`, live (polled every 5s - see
/// `watchVendorDeliveries`) so a status change shows up without a manual
/// refresh. No session required.
final vendorDeliveriesProvider =
    StreamProvider.family<List<VendorDelivery>, String>((ref, code) {
      return ref.watch(vendorRepositoryProvider).watchVendorDeliveries(code);
    });
