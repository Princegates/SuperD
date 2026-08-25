import 'user_role.dart';

class Profile {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final String? ghanaCardNumber;
  final String? vehicleNumber;
  final UserRole role;
  final bool isActive;
  final bool mustChangePassword;

  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    this.ghanaCardNumber,
    this.vehicleNumber,
    this.isActive = true,
    this.mustChangePassword = false,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      phone: map['phone'] as String?,
      ghanaCardNumber: map['ghana_card_number'] as String?,
      vehicleNumber: map['vehicle_number'] as String?,
      role: UserRole.fromString(map['role'] as String? ?? 'driver'),
      isActive: map['is_active'] as bool? ?? true,
      mustChangePassword: map['must_change_password'] as bool? ?? false,
    );
  }

  String get displayName => fullName.isNotEmpty ? fullName : email;
}
