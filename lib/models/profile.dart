import 'user_role.dart';

class Profile {
  final String id;
  final String email;
  final String fullName;
  final String? phone;
  final UserRole role;
  final bool isActive;

  const Profile({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    this.isActive = true,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      email: map['email'] as String? ?? '',
      fullName: map['full_name'] as String? ?? '',
      phone: map['phone'] as String?,
      role: UserRole.fromString(map['role'] as String? ?? 'driver'),
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  String get displayName => fullName.isNotEmpty ? fullName : email;
}
