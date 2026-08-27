/// App-wide settings - currently just the currency payments are recorded
/// in. Backed by the single-row `app_settings` table; see
/// `0017_app_settings.sql`.
class AppSettings {
  const AppSettings({required this.currency});

  final String currency;

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(currency: map['currency'] as String? ?? 'GHS');
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
