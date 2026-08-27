/// App-wide settings - the currency payments are recorded in, and the UI
/// theme. Backed by the single-row `app_settings` table; see
/// `0017_app_settings.sql` and `0018_app_settings_theme.sql`.
class AppSettings {
  const AppSettings({required this.currency, required this.theme});

  final String currency;
  final String theme;

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      currency: map['currency'] as String? ?? 'GHS',
      theme: map['theme'] as String? ?? 'navy_gold',
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
