/// A vehicle a customer can pick on the delivery request form, each with
/// its own flat surcharge added on top of the usual base-fare + per-km
/// price - see `vehicle_types` in `0051_vehicle_types.sql`. Exactly one
/// row has [isDefault] true at any time - the picker's starting
/// selection, motorcycle out of the box.
class VehicleType {
  final String id;
  final String name;
  final double extraFee;
  final bool isDefault;
  final DateTime createdAt;

  const VehicleType({
    required this.id,
    required this.name,
    required this.extraFee,
    required this.isDefault,
    required this.createdAt,
  });

  factory VehicleType.fromMap(Map<String, dynamic> map) {
    return VehicleType(
      id: map['id'] as String,
      name: map['name'] as String,
      extraFee: (map['extra_fee'] as num?)?.toDouble() ?? 0,
      isDefault: map['is_default'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
