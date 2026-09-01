/// A per-account toggleable action on top of the role model - see
/// `Profile.hasPermission` and `0072_permission_overrides.sql`. A super
/// admin can override any of these on one specific dispatcher/auditor
/// account, beyond what their role would normally allow/deny.
enum StaffPermission {
  createDeliveries,
  manageDrivers,
  assignDrivers,
  manageVendors;

  /// The key stored in `profiles.permission_overrides` and passed to the
  /// `has_permission()`/`register_vendor()` Postgres functions - must match
  /// `role_default_permission()` in `0072_permission_overrides.sql`.
  String get wireValue => switch (this) {
    StaffPermission.createDeliveries => 'create_deliveries',
    StaffPermission.manageDrivers => 'manage_drivers',
    StaffPermission.assignDrivers => 'assign_drivers',
    StaffPermission.manageVendors => 'manage_vendors',
  };

  String get label => switch (this) {
    StaffPermission.createDeliveries => 'Create deliveries',
    StaffPermission.manageDrivers => 'Manage drivers (add/edit/remove)',
    StaffPermission.assignDrivers => 'Assign drivers to deliveries',
    StaffPermission.manageVendors => 'Manage vendors (add/edit/remove)',
  };
}
