/// A named place within a zone (e.g. "American House" inside the "East
/// Legon" zone) - reference data a super admin adds when defining what a
/// zone actually covers.
class ZoneLocation {
  final String id;
  final String zoneId;
  final String name;
  final double? lat;
  final double? lng;

  const ZoneLocation({
    required this.id,
    required this.zoneId,
    required this.name,
    this.lat,
    this.lng,
  });

  factory ZoneLocation.fromMap(Map<String, dynamic> map) {
    return ZoneLocation(
      id: map['id'] as String,
      zoneId: map['zone_id'] as String,
      name: map['name'] as String,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
    );
  }

  bool get hasCoordinates => lat != null && lng != null;
}
