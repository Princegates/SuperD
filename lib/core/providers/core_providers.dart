import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/delivery_repository.dart';
import '../../data/repositories/profile_repository.dart';
import '../../models/profile.dart';

final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.watch(supabaseClientProvider));
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return ProfileRepository(ref.watch(supabaseClientProvider));
});

final deliveryRepositoryProvider = Provider<DeliveryRepository>((ref) {
  return DeliveryRepository(ref.watch(supabaseClientProvider));
});

/// Fires whenever the Supabase auth session changes (sign in / out / token
/// refresh). Everything else in the app that cares about "who is logged in"
/// derives from this.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).onAuthStateChange;
});

/// The signed-in user's app profile (role, name, ...), kept live so a role
/// change by an admin is picked up without a restart.
final currentProfileProvider = StreamProvider<Profile?>((ref) {
  final authState = ref.watch(authStateProvider).valueOrNull;
  final userId =
      authState?.session?.user.id ??
      ref.watch(supabaseClientProvider).auth.currentUser?.id;

  if (userId == null) {
    return Stream.value(null);
  }
  return ref.watch(profileRepositoryProvider).watchProfile(userId);
});
