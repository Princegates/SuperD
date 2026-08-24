import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/core_providers.dart';
import '../../models/delivery.dart';

final deliveryByIdProvider =
    StreamProvider.family<Delivery?, String>((ref, id) {
  return ref.watch(deliveryRepositoryProvider).watchById(id);
});
