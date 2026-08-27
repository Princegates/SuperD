import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_settings.dart';

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

  /// The single settings row, live - so a currency or theme change by a
  /// super admin is picked up everywhere else in the app without a
  /// restart. Not used for anything security-gating (see [fetchSettings])
  /// since realtime being briefly unavailable shouldn't block a decision
  /// that a plain fetch could make reliably instead.
  Stream<AppSettings> watchSettings() {
    return _client
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
        );
  }

  /// Changes the app-wide currency. Only takes effect if the caller is a
  /// super admin - enforced by RLS, not just this client.
  Future<void> updateCurrency(String currency) async {
    await _client
        .from(_table)
        .update({'currency': currency})
        .eq('id', true);
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
}
