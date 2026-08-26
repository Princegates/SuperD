import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';

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
