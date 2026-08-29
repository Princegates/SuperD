/// App-wide settings - the currency payments are recorded in, the UI
/// theme, whether a driver may sign in on the web dashboard, and the
/// automatic delivery-pricing rates. Backed by the single-row
/// `app_settings` table; see `0017_app_settings.sql`,
/// `0018_app_settings_theme.sql`, `0019_driver_web_login_toggle.sql`, and
/// `0022_delivery_pricing.sql`.
class AppSettings {
  const AppSettings({
    required this.currency,
    required this.theme,
    required this.allowDriverWebLogin,
    this.baseFare = 5,
    this.pricePerKm = 1.5,
    this.driverCommissionEnabled = true,
    this.commissionFlatFee = 0,
    this.freeDayDeliveryThreshold,
    this.zoneAutoAssignCap = 5,
    this.zoneDetectionRadiusKm = 5,
    this.supportPhone,
    this.adminAlertEmail,
    this.adminAlertPhone,
  });

  final String currency;
  final String theme;

  /// Off by default - the web dashboard is normally back-office only, and
  /// a driver signing in there gets signed straight back out (see
  /// app_router.dart). A super admin can flip this on temporarily to test
  /// the driver experience in a browser before the native Android/iOS
  /// apps are built and distributed.
  final bool allowDriverWebLogin;

  /// Flat fee every customer-submitted delivery starts with, before the
  /// distance charge. See `submit_delivery_request` in
  /// `0022_delivery_pricing.sql` for how this feeds into the quoted price.
  final double baseFare;

  /// Added per straight-line kilometer between the vendor and the
  /// dropoff, on top of [baseFare].
  final double pricePerKm;

  /// Master off-switch for driver commission - both this flat fee and the
  /// tiered daily fee ([DriverDailyFeeTier]) stop being charged/enforced
  /// while this is false, without losing their configured amounts. Meant
  /// for testing the app before it goes commercial - see
  /// `0041_driver_commission_toggle.sql`.
  final bool driverCommissionEnabled;

  /// Flat amount a driver owes the business per completed delivery - see
  /// `commission_payments` in `0029_commission_payments.sql`. 0 means
  /// commission tracking is effectively off. Ignored entirely while
  /// [driverCommissionEnabled] is false.
  final double commissionFlatFee;

  /// Automatic free-day incentive: every this many completed deliveries
  /// earns a driver 1 free commission day, credited to
  /// `driver_free_day_credits` and spent automatically - see
  /// `0032_commission_free_days.sql`. Null means the automatic rule is
  /// off (a dispatcher/super admin can still grant free days by hand
  /// either way).
  final int? freeDayDeliveryThreshold;

  /// Max active deliveries a driver can hold before automatic assignment
  /// stops picking them (in favour of the next-closest eligible driver)
  /// and a new request waits for a dispatcher instead once everyone's at
  /// the cap - see `submit_delivery_request()`/`driver_cancel_delivery()`
  /// in `0044_proximity_based_auto_assignment.sql`. No longer scoped to a
  /// zone - matching itself is now purely proximity-based (live GPS
  /// distance to the vendor), zones only affect pricing. Always 3-20.
  final int zoneAutoAssignCap;

  /// How close (km) a delivery's drop-off must be to a zone's pinned
  /// reference location for `detect_zone_for_point()` to trust it and use
  /// that zone - see `0040_zone_detection_radius_and_override.sql`.
  /// Beyond this, detection falls back to the vendor's own registered
  /// zone. Always 1-50.
  final double zoneDetectionRadiusKm;

  /// Business support/customer-service number, included in the
  /// driver-assigned SMS/email to the customer and vendor - see
  /// `0034_notifications_tracking_ratings.sql`. Null means it's just left
  /// out of those messages.
  final String? supportPhone;

  /// Where an internal alert - e.g. a driver cancelling a delivery
  /// mid-trip - is emailed. Separate from [supportPhone], which
  /// customers/vendors call, not an internal channel. Null means no
  /// email alert is sent - see `0036_driver_cancel_and_incident_reporting.sql`.
  final String? adminAlertEmail;

  /// Where the same internal alert is texted. Null means no SMS alert is
  /// sent.
  final String? adminAlertPhone;

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      currency: map['currency'] as String? ?? 'GHS',
      theme: map['theme'] as String? ?? 'navy_gold',
      allowDriverWebLogin: map['allow_driver_web_login'] as bool? ?? false,
      baseFare: (map['base_fare'] as num?)?.toDouble() ?? 5,
      pricePerKm: (map['price_per_km'] as num?)?.toDouble() ?? 1.5,
      driverCommissionEnabled:
          map['driver_commission_enabled'] as bool? ?? true,
      commissionFlatFee: (map['commission_flat_fee'] as num?)?.toDouble() ?? 0,
      freeDayDeliveryThreshold: (map['free_day_delivery_threshold'] as num?)
          ?.toInt(),
      zoneAutoAssignCap: (map['zone_auto_assign_cap'] as num?)?.toInt() ?? 5,
      zoneDetectionRadiusKm:
          (map['zone_detection_radius_km'] as num?)?.toDouble() ?? 5,
      supportPhone: map['support_phone'] as String?,
      adminAlertEmail: map['admin_alert_email'] as String?,
      adminAlertPhone: map['admin_alert_phone'] as String?,
    );
  }

  /// Currencies a super admin can pick from in Settings. Not exhaustive -
  /// just the ones this app is realistically deployed with - but nothing
  /// else in the app assumes one of these specifically, so adding another
  /// here is enough to support it.
  static const supportedCurrencies = [
    (code: 'GHS', label: 'Ghana Cedi (GHS)'),
    (code: 'NGN', label: 'Nigerian Naira (NGN)'),
    (code: 'KES', label: 'Kenyan Shilling (KES)'),
    (code: 'ZAR', label: 'South African Rand (ZAR)'),
    (code: 'XOF', label: 'West African CFA Franc (XOF)'),
    (code: 'USD', label: 'US Dollar (USD)'),
    (code: 'GBP', label: 'British Pound (GBP)'),
    (code: 'EUR', label: 'Euro (EUR)'),
  ];
}
