class Zone {
  final String id;
  final String name;

  /// Overrides the app-wide `base_fare`/`price_per_km` (Console > Settings)
  /// for vendors registered in this zone. Null means "use the app-wide
  /// default" - see `get_delivery_price_estimate()` /
  /// `submit_delivery_request()` in `0026_zone_pricing_and_auto_assign.sql`.
  final double? baseFare;
  final double? pricePerKm;

  const Zone({
    required this.id,
    required this.name,
    this.baseFare,
    this.pricePerKm,
  });

  factory Zone.fromMap(Map<String, dynamic> map) {
    return Zone(
      id: map['id'] as String,
      name: map['name'] as String,
      baseFare: (map['base_fare'] as num?)?.toDouble(),
      pricePerKm: (map['price_per_km'] as num?)?.toDouble(),
    );
  }
}
