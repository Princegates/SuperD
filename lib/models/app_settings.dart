/// App-wide settings - the currency payments are recorded in, the UI
/// theme, and whether a driver may sign in on the web dashboard. Backed by
/// the single-row `app_settings` table; see `0017_app_settings.sql`,
/// `0018_app_settings_theme.sql`, and `0019_driver_web_login_toggle.sql`.
class AppSettings {
  const AppSettings({
    required this.currency,
    required this.theme,
    required this.allowDriverWebLogin,
  });

  final String currency;
  final String theme;

  /// Off by default - the web dashboard is normally back-office only, and
  /// a driver signing in there gets signed straight back out (see
  /// app_router.dart). A super admin can flip this on temporarily to test
  /// the driver experience in a browser before the native Android/iOS
  /// apps are built and distributed.
  final bool allowDriverWebLogin;

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      currency: map['currency'] as String? ?? 'GHS',
      theme: map['theme'] as String? ?? 'navy_gold',
      allowDriverWebLogin: map['allow_driver_web_login'] as bool? ?? false,
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
