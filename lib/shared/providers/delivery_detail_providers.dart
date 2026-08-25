import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import '../../models/delivery.dart';
import '../../models/payment.dart';

final deliveryByIdProvider = StreamProvider.family<Delivery?, String>((
  ref,
  id,
) {
  return ref.watch(deliveryRepositoryProvider).watchById(id);
});

final paymentForDeliveryProvider = StreamProvider.family<Payment?, String>((
  ref,
  deliveryId,
) {
  return ref.watch(paymentRepositoryProvider).watchForDelivery(deliveryId);
});
