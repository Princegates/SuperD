import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/rider_rating.dart';

/// The signed-in rider's own rating. Aggregates only - see
/// `my_rating_summary()` in `0091_rider_own_rating.sql`.
final myRatingProvider = FutureProvider<RiderRating>((ref) async {
  // Rebuilds when the profile does, so a rider who has just been rated
  // sees it after the next refresh rather than only on a cold start.
  ref.watch(currentProfileProvider);
  return ref.watch(ratingRepositoryProvider).fetchMyRating();
});

/// A viewable link to the signed-in rider's own photograph.
///
/// Signed URLs expire, so this is deliberately tied to the provider's
/// lifetime rather than cached anywhere longer-lived.
final myPhotoUrlProvider = FutureProvider<String?>((ref) async {
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  return ref
      .watch(profileRepositoryProvider)
      .riderPhotoUrl(profile?.avatarPath);
});
