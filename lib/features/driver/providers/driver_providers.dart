import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';

final myDeliveriesProvider = StreamProvider<List<Delivery>>((ref) {
  final userId = ref.watch(supabaseClientProvider).auth.currentUser?.id;
  if (userId == null) return Stream.value(const []);
  return ref.watch(deliveryRepositoryProvider).watchDriverDeliveries(userId);
});
