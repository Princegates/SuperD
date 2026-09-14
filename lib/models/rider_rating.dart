/// A rider's own rating, as `my_rating_summary()` returns it.
///
/// Aggregates only - deliberately no customer comments. Those stay with
/// dispatch; see `0091_rider_own_rating.sql` for why.
class RiderRating {
  const RiderRating({
    required this.average,
    required this.count,
    required this.byStar,
  });

  /// Null when nobody has rated them yet, which is not the same as zero
  /// and must not be shown as one.
  final double? average;
  final int count;

  /// How many of each score, keyed 1-5.
  final Map<int, int> byStar;

  static const empty = RiderRating(average: null, count: 0, byStar: {});

  factory RiderRating.fromMap(Map<String, dynamic> map) {
    return RiderRating(
      average: (map['average'] as num?)?.toDouble(),
      count: (map['ratings_count'] as num?)?.toInt() ?? 0,
      byStar: {
        5: (map['five_star'] as num?)?.toInt() ?? 0,
        4: (map['four_star'] as num?)?.toInt() ?? 0,
        3: (map['three_star'] as num?)?.toInt() ?? 0,
        2: (map['two_star'] as num?)?.toInt() ?? 0,
        1: (map['one_star'] as num?)?.toInt() ?? 0,
      },
    );
  }

  bool get hasRatings => count > 0 && average != null;
}
