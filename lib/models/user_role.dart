enum UserRole {
  admin,
  driver;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (r) => r.name == value,
      orElse: () => UserRole.driver,
    );
  }

  String get label => switch (this) {
        UserRole.admin => 'Dispatcher',
        UserRole.driver => 'Driver',
      };
}
