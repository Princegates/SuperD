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

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      currency: map['currency'] as String? ?? 'GHS',
      theme: map['theme'] as String? ?? 'navy_gold',
      allowDriverWebLogin: map['allow_driver_web_login'] as bool? ?? false,
      baseFare: (map['base_fare'] as num?)?.toDouble() ?? 5,
      pricePerKm: (map['price_per_km'] as num?)?.toDouble() ?? 1.5,
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
