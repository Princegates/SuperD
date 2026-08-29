enum UserRole {
  driver,
  dispatcher,
  superAdmin,
  auditor;

  static UserRole fromString(String value) {
    return switch (value) {
      'driver' => UserRole.driver,
      'dispatcher' => UserRole.dispatcher,
      'super_admin' => UserRole.superAdmin,
      'auditor' => UserRole.auditor,
      _ => UserRole.driver,
    };
  }

  /// The value stored in Postgres (matches the `user_role` enum).
  String get wireValue => switch (this) {
    UserRole.driver => 'driver',
    UserRole.dispatcher => 'dispatcher',
    UserRole.superAdmin => 'super_admin',
    UserRole.auditor => 'auditor',
  };

  String get label => switch (this) {
    UserRole.driver => 'Driver',
    UserRole.dispatcher => 'Dispatcher',
    UserRole.superAdmin => 'Super Admin',
    UserRole.auditor => 'Auditor',
  };

  /// Dispatchers, super admins, and auditors share the same operations
  /// dashboard.
  bool get managesDeliveries => this != UserRole.driver;

  /// Only super admins can promote/demote other users.
  bool get managesRoles => this == UserRole.superAdmin;

  /// Sees every Console section a super admin does (Team, Overview,
  /// Reports, Finance, Audit log, Onboarding, Zones, Settings included) but
  /// can't write to the admin-level ones - see `0054_auditor_role_
  /// permissions.sql`. Day-to-day dispatch actions (assigning drivers,
  /// updating delivery status, recording payments, managing the driver
  /// roster) stay open, same as a plain dispatcher.
  bool get canViewAdminConsole =>
      this == UserRole.superAdmin || this == UserRole.auditor;
}
