/// A customer's rating of the driver on one delivery.
///
/// Written only by `submit_delivery_rating()` from the public tracking
/// page (`0034_notifications_tracking_ratings.sql`); the admin side reads
/// these and never writes them.
class DeliveryRating {
  const DeliveryRating({
    required this.id,
    required this.deliveryId,
    required this.driverId,
    required this.rating,
    required this.createdAt,
    this.comment,
  });

  final String id;
  final String deliveryId;
  final String driverId;

  /// 1-5, enforced by a check constraint on the table.
  final int rating;

  /// What the customer typed, if anything. Usually the useful part.
  final String? comment;

  final DateTime createdAt;

  /// Whether this is the kind of rating someone should actually look at.
  bool get needsAttention => rating <= 3;

  static DeliveryRating fromMap(Map<String, dynamic> map) {
    return DeliveryRating(
      id: map['id'] as String,
      deliveryId: map['delivery_id'] as String,
      driverId: map['driver_id'] as String,
      rating: (map['rating'] as num).toInt(),
      comment: (map['comment'] as String?)?.trim().isEmpty ?? true
          ? null
          : (map['comment'] as String).trim(),
      createdAt: DateTime.parse(map['created_at'] as String).toLocal(),
    );
  }
}

/// One driver's rating record in aggregate, from `driver_rating_summary()`
/// (`0087_driver_rating_summary.sql`) - averaged in the database so the
/// list doesn't have to pull every rating row to show a number.
class DriverRatingSummary {
  const DriverRatingSummary({
    required this.driverId,
    required this.average,
    required this.count,
  });

  final String driverId;
  final double average;
  final int count;

  static DriverRatingSummary fromMap(Map<String, dynamic> map) {
    return DriverRatingSummary(
      driverId: map['driver_id'] as String,
      average: (map['average'] as num).toDouble(),
      count: (map['ratings_count'] as num).toInt(),
    );
  }
}
