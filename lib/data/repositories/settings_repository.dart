import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_settings.dart';
import '../../shared/utils/resilient_stream.dart';

class SettingsRepository {
  SettingsRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'app_settings';

  /// One-time plain REST fetch of the settings row - no realtime
  /// subscription involved. Used for the driver-web-login gate in the
  /// router: that decision needs to be reliable every time, and a
  /// WebSocket-based realtime channel is one more thing that can be slow
  /// to connect or time out (seen in practice) - a plain fetch either
  /// succeeds or fails outright, with nothing to hang waiting on.
  Future<AppSettings> fetchSettings() async {
    final row = await _client.from(_table).select().maybeSingle();
    return row == null
        ? const AppSettings(
            currency: 'GHS',
            theme: 'navy_gold',
            allowDriverWebLogin: false,
          )
        : AppSettings.fromMap(row);
  }

  Future<void> updatePricing({
    required double baseFare,
    required double pricePerKm,
  }) async {
    await _client
        .from(_table)
        .update({'base_fare': baseFare, 'price_per_km': pricePerKm})
        .eq('id', true);
  }

  /// The single settings row, live - so a currency or theme change by a
  /// super admin is picked up everywhere else in the app without a
  /// restart. Not used for anything security-gating (see [fetchSettings])
  /// since realtime being briefly unavailable shouldn't block a decision
  /// that a plain fetch could make reliably instead.
  Stream<AppSettings> watchSettings() {
    return resilientRealtimeStream(
      () => _client
          .from(_table)
          .stream(primaryKey: ['id'])
          .map(
            (rows) => rows.isEmpty
                ? const AppSettings(
                    currency: 'GHS',
                    theme: 'navy_gold',
                    allowDriverWebLogin: false,
                  )
                : AppSettings.fromMap(rows.first),
          ),
    );
  }

  /// Changes the app-wide currency. Only takes effect if the caller is a
  /// super admin - enforced by RLS, not just this client.
  Future<void> updateCurrency(String currency) async {
    await _client.from(_table).update({'currency': currency}).eq('id', true);
  }

  /// Changes the app-wide UI theme (see [ThemePreset] in app_theme.dart).
  /// Only takes effect if the caller is a super admin - enforced by RLS.
  Future<void> updateTheme(String themeKey) async {
    await _client.from(_table).update({'theme': themeKey}).eq('id', true);
  }

  /// Toggles whether a driver may sign in on the web dashboard - see
  /// [AppSettings.allowDriverWebLogin]. Only takes effect if the caller is
  /// a super admin - enforced by RLS.
  Future<void> setAllowDriverWebLogin(bool allow) async {
    await _client
        .from(_table)
        .update({'allow_driver_web_login': allow})
        .eq('id', true);
  }

  /// Master off-switch for driver commission - see
  /// [AppSettings.driverCommissionEnabled]. Only takes effect if the caller
  /// is a super admin - enforced by RLS.
  Future<void> setDriverCommissionEnabled(bool enabled) async {
    await _client
        .from(_table)
        .update({'driver_commission_enabled': enabled})
        .eq('id', true);
  }

  /// Changes the flat commission fee owed per completed delivery - see
  /// [AppSettings.commissionFlatFee]. Only takes effect going forward;
  /// commission already recorded keeps whatever fee applied at the time.
  Future<void> updateCommissionFlatFee(double flatFee) async {
    await _client
        .from(_table)
        .update({'commission_flat_fee': flatFee})
        .eq('id', true);
  }

  /// Changes the percentage-of-payment commission added to the flat fee -
  /// see [AppSettings.commissionPercentage]. Only takes effect going
  /// forward; commission already recorded keeps whatever rate applied at
  /// the time.
  Future<void> updateCommissionPercentage(double percentage) async {
    if (percentage < 0 || percentage > 100) {
      throw ArgumentError(
        'The commission percentage must be between 0 and 100.',
      );
    }
    await _client
        .from(_table)
        .update({'commission_percentage': percentage})
        .eq('id', true);
  }

  /// Changes (or clears) the automatic free-day threshold - see
  /// [AppSettings.freeDayDeliveryThreshold]. Null turns the automatic
  /// rule off; manual grants from Console > Daily Fees are unaffected
  /// either way.
  Future<void> updateFreeDayThreshold(int? threshold) async {
    if (threshold != null && threshold <= 0) {
      throw ArgumentError('The delivery threshold must be a positive number.');
    }
    await _client
        .from(_table)
        .update({'free_day_delivery_threshold': threshold})
        .eq('id', true);
  }

  /// Changes the automatic-assignment cap - see
  /// [AppSettings.zoneAutoAssignCap]. The database itself also enforces
  /// 3-to-20 (see `app_settings_zone_auto_assign_cap_check` in
  /// `0033_zone_auto_recognition_and_cap.sql`, column name unchanged
  /// since - just its meaning, see `0044_proximity_based_auto_assignment.sql`),
  /// this is just the friendlier client-side check.
  Future<void> updateZoneAutoAssignCap(int cap) async {
    if (cap < 3 || cap > 20) {
      throw ArgumentError('The cap must be between 3 and 20.');
    }
    await _client
        .from(_table)
        .update({'zone_auto_assign_cap': cap})
        .eq('id', true);
  }

  /// Changes the automatic zone-detection radius - see
  /// [AppSettings.zoneDetectionRadiusKm]. The database itself also
  /// enforces 1-to-50 (see `app_settings_zone_detection_radius_km_check`
  /// in `0040_zone_detection_radius_and_override.sql`), this is just the
  /// friendlier client-side check.
  Future<void> updateZoneDetectionRadius(double km) async {
    if (km < 1 || km > 50) {
      throw ArgumentError('The radius must be between 1 and 50 km.');
    }
    await _client
        .from(_table)
        .update({'zone_detection_radius_km': km})
        .eq('id', true);
  }

  /// Changes the automatic-assignment radius - see
  /// [AppSettings.autoAssignRadiusKm]. The database itself also enforces
  /// 1-to-100 (see `app_settings_auto_assign_radius_km_check` in
  /// `0052_high_performer_assignment_fallback.sql`), this is just the
  /// friendlier client-side check.
  Future<void> updateAutoAssignRadius(double km) async {
    if (km < 1 || km > 100) {
      throw ArgumentError('The radius must be between 1 and 100 km.');
    }
    await _client
        .from(_table)
        .update({'auto_assign_radius_km': km})
        .eq('id', true);
  }

  /// Changes (or clears) the support number included in the
  /// driver-assigned SMS/email - see [AppSettings.supportPhone].
  Future<void> updateSupportPhone(String? phone) async {
    await _client.from(_table).update({'support_phone': phone}).eq('id', true);
  }

  /// Changes (or clears) where an internal alert (a driver cancelling
  /// mid-trip) is emailed - see [AppSettings.adminAlertEmail].
  Future<void> updateAdminAlertEmail(String? email) async {
    await _client
        .from(_table)
        .update({'admin_alert_email': email})
        .eq('id', true);
  }

  /// Changes (or clears) where the same internal alert is texted - see
  /// [AppSettings.adminAlertPhone].
  Future<void> updateAdminAlertPhone(String? phone) async {
    await _client
        .from(_table)
        .update({'admin_alert_phone': phone})
        .eq('id', true);
  }

  /// Master switch for the one-time vendor subscription fee - see
  /// [AppSettings.vendorSubscriptionEnabled]. Only takes effect if the
  /// caller is a super admin - enforced by RLS.
  Future<void> setVendorSubscriptionEnabled(bool enabled) async {
    await _client
        .from(_table)
        .update({'vendor_subscription_enabled': enabled})
        .eq('id', true);
  }

  /// Changes the one-time vendor subscription fee - see
  /// [AppSettings.vendorSubscriptionFee]. Only affects new registrations
  /// going forward.
  Future<void> updateVendorSubscriptionFee(double fee) async {
    if (fee < 0) {
      throw ArgumentError('The fee cannot be negative.');
    }
    await _client
        .from(_table)
        .update({'vendor_subscription_fee': fee})
        .eq('id', true);
  }
}
