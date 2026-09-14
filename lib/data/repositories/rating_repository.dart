import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/delivery_rating.dart';
import '../../models/rider_rating.dart';

/// Read access to what customers said about drivers.
///
/// Every method here is a read: ratings are only ever written by
/// `submit_delivery_rating()` from the customer's own tracking page
/// (`0034_notifications_tracking_ratings.sql`), which has no admin-side
/// equivalent by design - staff cannot rate their own drivers.
///
/// RLS ("delivery_ratings: dispatcher reads all") does the scoping, so a
/// driver calling any of this gets an empty result rather than an error.
class RatingRepository {
  RatingRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'delivery_ratings';

  /// Every driver's average and how many ratings it rests on, keyed by
  /// driver id. Aggregated in the database (`driver_rating_summary()`,
  /// `0087_driver_rating_summary.sql`) rather than here, so the roster
  /// costs one small row per driver instead of every rating ever left.
  Future<Map<String, DriverRatingSummary>> fetchSummary() async {
    final rows = await _client.rpc('driver_rating_summary') as List<dynamic>;
    return {
      for (final row in rows)
        (row as Map<String, dynamic>)['driver_id'] as String:
            DriverRatingSummary.fromMap(row),
    };
  }

  /// The most recent ratings, newest first.
  ///
  /// [onlyPoor] narrows to the ones worth acting on - a three or below.
  /// A five with no comment tells you nothing you need to do today; a two
  /// with a sentence attached is the whole reason to have this screen.
  Future<List<DeliveryRating>> fetchRecent({
    int limit = 20,
    bool onlyPoor = false,
  }) async {
    var query = _client.from(_table).select();
    if (onlyPoor) query = query.lte('rating', 3);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return rows.map(DeliveryRating.fromMap).toList();
  }

  /// The signed-in rider's own rating - average, how many it is drawn
  /// from, and the spread. Aggregates only; the customer comments stay
  /// with dispatch. See `my_rating_summary()` in 0092.
  Future<RiderRating> fetchMyRating() async {
    final rows = await _client.rpc('my_rating_summary') as List<dynamic>;
    if (rows.isEmpty) return RiderRating.empty;
    return RiderRating.fromMap(rows.first as Map<String, dynamic>);
  }
}
