import 'driver_vehicle_type.dart';
import 'user_role.dart';

class Profile {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? ghanaCardNumber;
  final String? vehicleNumber;
  final DriverVehicleType? vehicleType;
  final DateTime? dateOfBirth;
  final String? residentialAddress;
  final String? zoneId;
  final UserRole role;
  final bool isActive;
  final bool isOnline;
  final bool isFrozen;
  final bool mustChangePassword;
  final DateTime? createdAt;
  final double? lastLat;
  final double? lastLng;
  final DateTime? locationUpdatedAt;

  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    this.ghanaCardNumber,
    this.vehicleNumber,
    this.vehicleType,
    this.dateOfBirth,
    this.residentialAddress,
    this.zoneId,
    this.isActive = true,
    this.isOnline = false,
    this.isFrozen = false,
    this.mustChangePassword = false,
    this.createdAt,
    this.lastLat,
    this.lastLng,
    this.locationUpdatedAt,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      phone: map['phone'] as String?,
      ghanaCardNumber: map['ghana_card_number'] as String?,
      vehicleNumber: map['vehicle_number'] as String?,
      vehicleType: DriverVehicleType.fromString(map['vehicle_type'] as String?),
      dateOfBirth: map['date_of_birth'] == null
          ? null
          : DateTime.tryParse(map['date_of_birth'] as String),
      residentialAddress: map['residential_address'] as String?,
      zoneId: map['zone_id'] as String?,
      role: UserRole.fromString(map['role'] as String? ?? 'driver'),
      isActive: map['is_active'] as bool? ?? true,
      isOnline: map['is_online'] as bool? ?? false,
      isFrozen: map['is_frozen'] as bool? ?? false,
      mustChangePassword: map['must_change_password'] as bool? ?? false,
      createdAt: map['created_at'] == null
          ? null
          : DateTime.tryParse(map['created_at'] as String),
      lastLat: (map['last_lat'] as num?)?.toDouble(),
      lastLng: (map['last_lng'] as num?)?.toDouble(),
      locationUpdatedAt: map['location_updated_at'] == null
          ? null
          : DateTime.tryParse(map['location_updated_at'] as String),
    );
  }

  String get displayName => fullName.isNotEmpty ? fullName : email;

  bool get hasRecentLocation =>
      lastLat != null &&
      lastLng != null &&
      locationUpdatedAt != null &&
      DateTime.now().difference(locationUpdatedAt!) <
          const Duration(minutes: 15);
}
