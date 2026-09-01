import 'driver_vehicle_type.dart';
import 'staff_permission.dart';
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

  /// Driver-only credentials - see `0070_driver_license_and_insurance.sql`.
  /// Distinct from [ghanaCardNumber] (national ID). The driving licence
  /// fields are required at signup/creation time going forward (nullable
  /// here only because an existing driver from before this migration has
  /// none on file yet); the insurance fields are collected the same way
  /// but stay optional - not every driver has a policy on file, and the
  /// form deliberately doesn't call that out as optional either.
  final String? drivingLicenseNumber;
  final DateTime? drivingLicenseExpiry;
  final String? vehicleInsuranceNumber;
  final DateTime? vehicleInsuranceExpiry;

  /// Super-admin-only pin to one specific `driver_daily_fee_tiers` row -
  /// see `daily_fee_tier_override_id` in `0038_daily_fee_tier_overrides.sql`.
  /// Null means the normal automatic tier-by-delivery-count behavior.
  final String? dailyFeeTierOverrideId;

  /// A dispatcher/super-admin-granted temporary bypass of the daily-fee/
  /// commission access block, until this moment - null means none active.
  /// Doesn't change what's actually owed, just lifts the block meanwhile -
  /// see `payment_access_override_until` in
  /// `0068_driver_payment_access_override.sql`.
  final DateTime? paymentAccessOverrideUntil;
  final UserRole role;

  /// Per-account permission overrides on top of [role]'s defaults - a key
  /// present here (true or false) wins; a key absent falls back to
  /// [hasPermission]'s role-based default. Only ever non-empty for a
  /// dispatcher/auditor a super admin has specifically overridden - see
  /// `0072_permission_overrides.sql`.
  final Map<String, bool> permissionOverrides;
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
    this.drivingLicenseNumber,
    this.drivingLicenseExpiry,
    this.vehicleInsuranceNumber,
    this.vehicleInsuranceExpiry,
    this.dailyFeeTierOverrideId,
    this.paymentAccessOverrideUntil,
    this.permissionOverrides = const {},
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
      drivingLicenseNumber: map['driving_license_number'] as String?,
      drivingLicenseExpiry: map['driving_license_expiry'] == null
          ? null
          : DateTime.tryParse(map['driving_license_expiry'] as String),
      vehicleInsuranceNumber: map['vehicle_insurance_number'] as String?,
      vehicleInsuranceExpiry: map['vehicle_insurance_expiry'] == null
          ? null
          : DateTime.tryParse(map['vehicle_insurance_expiry'] as String),
      dailyFeeTierOverrideId: map['daily_fee_tier_override_id'] as String?,
      paymentAccessOverrideUntil: map['payment_access_override_until'] == null
          ? null
          : DateTime.tryParse(map['payment_access_override_until'] as String),
      role: UserRole.fromString(map['role'] as String? ?? 'driver'),
      permissionOverrides: (map['permission_overrides'] as Map<String, dynamic>?)
              ?.map((key, value) => MapEntry(key, value as bool)) ??
          const {},
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

  /// Whether this account may do [permission] right now - an explicit
  /// override always wins; absent that, a super admin always can, a
  /// dispatcher/auditor can for every [StaffPermission] as things stand
  /// today, and a driver never can. Mirrors `has_permission()`/
  /// `role_default_permission()` in `0072_permission_overrides.sql` - the
  /// database is still the real enforcement point (this is only for
  /// deciding what the UI shows), so keep the two in sync if either
  /// changes.
  bool hasPermission(StaffPermission permission) {
    if (role == UserRole.superAdmin) return true;
    final override = permissionOverrides[permission.wireValue];
    if (override != null) return override;
    return roleDefaultPermission(permission);
  }

  /// What [role] gets for [permission] with any override ignored - use
  /// this only to label the "Default (...)" choice in the permissions
  /// editor; [hasPermission] (override-aware) is what actually decides
  /// access. Mirrors `role_default_permission()` in
  /// `0072_permission_overrides.sql`.
  bool roleDefaultPermission(StaffPermission permission) {
    return role == UserRole.superAdmin ||
        role == UserRole.dispatcher ||
        role == UserRole.auditor;
  }

  /// Whether a granted [paymentAccessOverrideUntil] is still in effect
  /// right now.
  bool get hasActivePaymentAccessOverride =>
      paymentAccessOverrideUntil != null &&
      paymentAccessOverrideUntil!.isAfter(DateTime.now());

  bool get hasRecentLocation =>
      lastLat != null &&
      lastLng != null &&
      locationUpdatedAt != null &&
      DateTime.now().difference(locationUpdatedAt!) <
          const Duration(minutes: 15);
}
