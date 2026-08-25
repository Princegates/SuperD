enum UserRole {
  driver,
  dispatcher,
  superAdmin;

  static UserRole fromString(String value) {
    return switch (value) {
      'driver' => UserRole.driver,
      'dispatcher' => UserRole.dispatcher,
      'super_admin' => UserRole.superAdmin,
      _ => UserRole.driver,
    };
  }

  /// The value stored in Postgres (matches the `user_role` enum).
  String get wireValue => switch (this) {
    UserRole.driver => 'driver',
    UserRole.dispatcher => 'dispatcher',
    UserRole.superAdmin => 'super_admin',
  };

  String get label => switch (this) {
    UserRole.driver => 'Driver',
    UserRole.dispatcher => 'Dispatcher',
    UserRole.superAdmin => 'Super Admin',
  };

  /// Dispatchers and super admins share the same operations dashboard.
  bool get managesDeliveries => this != UserRole.driver;

  /// Only super admins can promote/demote other users.
  bool get managesRoles => this == UserRole.superAdmin;
}
