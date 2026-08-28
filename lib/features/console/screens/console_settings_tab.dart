import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_settings.dart';
import '../../../models/driver_daily_fee_tier.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';

/// Super-admin-only app-wide settings: the currency payments are recorded
/// and displayed in everywhere else in the app (delivery fees, the
/// Finance tab, payment cards on delivery detail), the UI theme, and
/// whether a driver may sign in on the web dashboard for testing.
class ConsoleSettingsTab extends ConsumerStatefulWidget {
  const ConsoleSettingsTab({super.key});

  @override
  ConsumerState<ConsoleSettingsTab> createState() => _ConsoleSettingsTabState();
}

class _ConsoleSettingsTabState extends ConsumerState<ConsoleSettingsTab> {
  final _baseFareController = TextEditingController();
  final _pricePerKmController = TextEditingController();
  final _commissionFeeController = TextEditingController();
  final _freeDayThresholdController = TextEditingController();
  final _zoneAutoAssignCapController = TextEditingController();
  final _supportPhoneController = TextEditingController();
  final _adminAlertEmailController = TextEditingController();
  final _adminAlertPhoneController = TextEditingController();
  String? _syncedFromSettings;
  bool _isSavingPricing = false;
  bool _isSavingCommission = false;
  bool _isSavingFreeDayThreshold = false;
  bool _isSavingZoneAutoAssignCap = false;
  bool _isSavingSupportPhone = false;
  bool _isSavingAdminAlerts = false;

  @override
  void dispose() {
    _baseFareController.dispose();
    _pricePerKmController.dispose();
    _commissionFeeController.dispose();
    _freeDayThresholdController.dispose();
    _zoneAutoAssignCapController.dispose();
    _supportPhoneController.dispose();
    _adminAlertEmailController.dispose();
    _adminAlertPhoneController.dispose();
    super.dispose();
  }

  Future<void> _changeCurrency(WidgetRef ref, String from, String to) async {
    if (to == from) return;
    await ref.read(settingsRepositoryProvider).updateCurrency(to);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'currency_changed',
      entityType: 'app_settings',
      summary: 'Changed app currency from $from to $to',
    );
  }

  Future<void> _changeTheme(WidgetRef ref, String from, String to) async {
    if (to == from) return;
    await ref.read(settingsRepositoryProvider).updateTheme(to);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'theme_changed',
      entityType: 'app_settings',
      summary:
          'Changed app theme from ${themePresetFor(from).label} to '
          '${themePresetFor(to).label}',
    );
  }

  Future<void> _toggleDriverWebLogin(WidgetRef ref, bool allow) async {
    await ref.read(settingsRepositoryProvider).setAllowDriverWebLogin(allow);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'driver_web_login_toggled',
      entityType: 'app_settings',
      summary: allow
          ? 'Enabled driver sign-in on the web dashboard'
          : 'Disabled driver sign-in on the web dashboard',
    );
  }

  Future<void> _savePricing(
    AppSettings settings,
    double baseFare,
    double pricePerKm,
  ) async {
    setState(() => _isSavingPricing = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .updatePricing(baseFare: baseFare, pricePerKm: pricePerKm);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'pricing_changed',
        entityType: 'app_settings',
        summary:
            'Changed delivery pricing to base fare '
            '${settings.currency} ${baseFare.toStringAsFixed(2)} + '
            '${settings.currency} ${pricePerKm.toStringAsFixed(2)}/km',
      );
    } finally {
      if (mounted) setState(() => _isSavingPricing = false);
    }
  }

  Future<void> _saveCommission(AppSettings settings, double flatFee) async {
    setState(() => _isSavingCommission = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateCommissionFlatFee(flatFee);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'commission_fee_changed',
        entityType: 'app_settings',
        summary:
            'Changed driver commission to ${settings.currency} '
            '${flatFee.toStringAsFixed(2)} per delivery',
      );
    } finally {
      if (mounted) setState(() => _isSavingCommission = false);
    }
  }

  Future<void> _saveFreeDayThreshold(int? threshold) async {
    setState(() => _isSavingFreeDayThreshold = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .updateFreeDayThreshold(threshold);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'free_day_threshold_changed',
        entityType: 'app_settings',
        summary: threshold == null
            ? 'Turned off the automatic free-day incentive'
            : 'Set the automatic free-day incentive to every $threshold '
                  'completed deliveries',
      );
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSavingFreeDayThreshold = false);
    }
  }

  Future<void> _saveZoneAutoAssignCap(int cap) async {
    setState(() => _isSavingZoneAutoAssignCap = true);
    try {
      await ref.read(settingsRepositoryProvider).updateZoneAutoAssignCap(cap);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'zone_auto_assign_cap_changed',
        entityType: 'app_settings',
        summary:
            'Changed the automatic-assignment cap to $cap active '
            'deliveries per driver',
      );
    } on ArgumentError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message.toString())));
      }
    } finally {
      if (mounted) setState(() => _isSavingZoneAutoAssignCap = false);
    }
  }

  Future<void> _saveSupportPhone(String? phone) async {
    setState(() => _isSavingSupportPhone = true);
    try {
      await ref.read(settingsRepositoryProvider).updateSupportPhone(phone);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'support_phone_changed',
        entityType: 'app_settings',
        summary: phone == null
            ? 'Removed the support phone number'
            : 'Changed the support phone number to $phone',
      );
    } finally {
      if (mounted) setState(() => _isSavingSupportPhone = false);
    }
  }

  Future<void> _saveAdminAlerts(String? email, String? phone) async {
    setState(() => _isSavingAdminAlerts = true);
    try {
      await ref.read(settingsRepositoryProvider).updateAdminAlertEmail(email);
      await ref.read(settingsRepositoryProvider).updateAdminAlertPhone(phone);
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: 'admin_alerts_changed',
        entityType: 'app_settings',
        summary: 'Changed the internal alert email/phone',
      );
    } finally {
      if (mounted) setState(() => _isSavingAdminAlerts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(appSettingsProvider);

    return AsyncValueView<AppSettings>(
      value: settingsState,
      data: (settings) {
        // Sync the text fields from the live settings row once per value
        // (not on every rebuild) so a super admin's in-progress edit isn't
        // clobbered by their own keystroke triggering a rebuild.
        final syncKey =
            '${settings.baseFare}|${settings.pricePerKm}|'
            '${settings.commissionFlatFee}|'
            '${settings.freeDayDeliveryThreshold}|'
            '${settings.zoneAutoAssignCap}|${settings.supportPhone}|'
            '${settings.adminAlertEmail}|${settings.adminAlertPhone}';
        if (_syncedFromSettings != syncKey) {
          _syncedFromSettings = syncKey;
          _baseFareController.text = settings.baseFare.toStringAsFixed(2);
          _pricePerKmController.text = settings.pricePerKm.toStringAsFixed(2);
          _commissionFeeController.text = settings.commissionFlatFee
              .toStringAsFixed(2);
          _freeDayThresholdController.text =
              settings.freeDayDeliveryThreshold?.toString() ?? '';
          _zoneAutoAssignCapController.text = settings.zoneAutoAssignCap
              .toString();
          _supportPhoneController.text = settings.supportPhone ?? '';
          _adminAlertEmailController.text = settings.adminAlertEmail ?? '';
          _adminAlertPhoneController.text = settings.adminAlertPhone ?? '';
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Support phone number',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Included in the SMS/email a customer and vendor get '
                      'when a driver is assigned, so they have a number to '
                      'call if something goes wrong with the delivery or '
                      'the driver. Leave blank to leave it out of those '
                      'messages.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _supportPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Support phone (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSavingSupportPhone
                              ? null
                              : () => _saveSupportPhone(
                                  _supportPhoneController.text.trim().isEmpty
                                      ? null
                                      : _supportPhoneController.text.trim(),
                                ),
                          child: _isSavingSupportPhone
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Internal alerts',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Where you're notified if a driver cancels a delivery "
                      "mid-trip - separate from the support number above, "
                      "which is for customers and vendors to call, not you. "
                      'Leave either blank to skip that channel.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _adminAlertEmailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Alert email (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _adminAlertPhoneController,
                            keyboardType: TextInputType.phone,
                            decoration: const InputDecoration(
                              labelText: 'Alert phone (optional)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSavingAdminAlerts
                              ? null
                              : () => _saveAdminAlerts(
                                  _adminAlertEmailController.text.trim().isEmpty
                                      ? null
                                      : _adminAlertEmailController.text.trim(),
                                  _adminAlertPhoneController.text.trim().isEmpty
                                      ? null
                                      : _adminAlertPhoneController.text.trim(),
                                ),
                          child: _isSavingAdminAlerts
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Currency',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Used for delivery fees and everywhere payments are '
                      'shown across the app. Changing it only affects new '
                      'payments - amounts already recorded keep the '
                      'currency they were entered in.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: settings.currency,
                      decoration: const InputDecoration(
                        labelText: 'App currency',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in AppSettings.supportedCurrencies)
                          DropdownMenuItem(value: c.code, child: Text(c.label)),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        _changeCurrency(ref, settings.currency, value);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Theme',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'The brand color everyone sees across the app - app '
                      'bars, buttons, highlights. Applies for every user, '
                      'not just you.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final preset in kThemePresets)
                          _ThemeSwatch(
                            preset: preset,
                            selected: preset.key == settings.theme,
                            onTap: () =>
                                _changeTheme(ref, settings.theme, preset.key),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Delivery pricing',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A customer submitting a request is quoted the base '
                      'fare plus this rate per kilometer between the '
                      "vendor and the drop-off (straight-line distance, "
                      "not actual road distance). Doesn't affect deliveries "
                      'already submitted.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _baseFareController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Base fare (${settings.currency})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _pricePerKmController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Per km (${settings.currency})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _isSavingPricing
                            ? null
                            : () {
                                final baseFare = double.tryParse(
                                  _baseFareController.text.trim(),
                                );
                                final pricePerKm = double.tryParse(
                                  _pricePerKmController.text.trim(),
                                );
                                if (baseFare == null || pricePerKm == null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Enter valid numbers for both fields.',
                                      ),
                                    ),
                                  );
                                  return;
                                }
                                _savePricing(settings, baseFare, pricePerKm);
                              },
                        child: _isSavingPricing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Save pricing'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Automatic assignment cap',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A customer-submitted request in a zone with an '
                      'available driver is assigned to them automatically '
                      "- but only up to this many active deliveries at "
                      'once. Once a driver hits the cap, further requests '
                      "in that zone wait at Pending for a dispatcher, "
                      'rather than piling onto them. Must be between 3 '
                      'and 20.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _zoneAutoAssignCapController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Active deliveries per driver (3-20)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSavingZoneAutoAssignCap
                              ? null
                              : () {
                                  final cap = int.tryParse(
                                    _zoneAutoAssignCapController.text.trim(),
                                  );
                                  if (cap == null || cap < 3 || cap > 20) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enter a whole number between 3 '
                                          'and 20.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  _saveZoneAutoAssignCap(cap);
                                },
                          child: _isSavingZoneAutoAssignCap
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Driver commission',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'A flat amount a driver owes the business for every '
                      'delivery they complete - recorded automatically in '
                      'Console > Commission the moment a delivery is marked '
                      "delivered. Set to 0 to stop tracking it. Doesn't "
                      'affect commission already recorded.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commissionFeeController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText:
                                  'Commission per delivery (${settings.currency})',
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSavingCommission
                              ? null
                              : () {
                                  final flatFee = double.tryParse(
                                    _commissionFeeController.text.trim(),
                                  );
                                  if (flatFee == null) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Enter a valid number.'),
                                      ),
                                    );
                                    return;
                                  }
                                  _saveCommission(settings, flatFee);
                                },
                          child: _isSavingCommission
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            _DailyFeeTiersCard(currency: settings.currency),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free day incentive',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Automatically rewards a driver with 1 free '
                      "commission day every time they hit this many "
                      'completed deliveries - leave blank to turn the '
                      'automatic rule off. You can also grant free days by '
                      'hand at any time from Console > Daily Fees, '
                      'regardless of this setting.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _freeDayThresholdController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText:
                                  'Deliveries per free day (blank = off)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: _isSavingFreeDayThreshold
                              ? null
                              : () {
                                  final text = _freeDayThresholdController.text
                                      .trim();
                                  if (text.isEmpty) {
                                    _saveFreeDayThreshold(null);
                                    return;
                                  }
                                  final threshold = int.tryParse(text);
                                  if (threshold == null || threshold <= 0) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Enter a positive whole number, or '
                                          'leave blank to turn it off.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  _saveFreeDayThreshold(threshold);
                                },
                          child: _isSavingFreeDayThreshold
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Allow driver sign-in on the web',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Switch(
                          value: settings.allowDriverWebLogin,
                          onChanged: (value) =>
                              _toggleDriverWebLogin(ref, value),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Normally a driver account gets signed straight back '
                      'out on this dashboard - it\'s back-office only, '
                      'drivers use the mobile app. Turn this on to test the '
                      'driver experience in a browser before the Android/iOS '
                      'apps are ready, then turn it back off once they are.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Admin editor for the driver daily fee's tier list - "at least N
/// deliveries today owes X" rows, add/edit/remove, live via
/// [dailyFeeTiersProvider]. Replaces the old single flat-amount field: see
/// `driver_daily_fee_tiers` in `0037_tiered_daily_fee.sql`.
class _DailyFeeTiersCard extends ConsumerWidget {
  const _DailyFeeTiersCard({required this.currency});

  final String currency;

  Future<void> _openTierDialog(
    BuildContext context,
    WidgetRef ref, {
    DriverDailyFeeTier? existing,
  }) async {
    final minController = TextEditingController(
      text: existing?.minDeliveries.toString() ?? '',
    );
    final amountController = TextEditingController(
      text: existing?.amount.toStringAsFixed(2) ?? '',
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Add tier' : 'Edit tier'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: minController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'At least this many deliveries today',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: 'Fee ($currency)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save != true || !context.mounted) return;

    final minDeliveries = int.tryParse(minController.text.trim());
    final amount = double.tryParse(amountController.text.trim());
    if (minDeliveries == null ||
        minDeliveries < 0 ||
        amount == null ||
        amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter a whole number of deliveries (0 or more) and a fee '
            'greater than 0.',
          ),
        ),
      );
      return;
    }

    final repo = ref.read(driverDailyFeeRepositoryProvider);
    try {
      if (existing == null) {
        await repo.addTier(minDeliveries: minDeliveries, amount: amount);
      } else {
        await repo.updateTier(
          id: existing.id,
          minDeliveries: minDeliveries,
          amount: amount,
        );
      }
      if (!context.mounted) return;
      await logAuditEvent(
        ref.read(supabaseClientProvider),
        action: existing == null
            ? 'daily_fee_tier_added'
            : 'daily_fee_tier_changed',
        entityType: 'driver_daily_fee_tiers',
        summary:
            '${existing == null ? 'Added' : 'Changed'} a daily fee tier: '
            '$minDeliveries+ deliveries -> $currency '
            '${amount.toStringAsFixed(2)}',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not save that tier: $e')));
      }
    }
  }

  Future<void> _deleteTier(
    BuildContext context,
    WidgetRef ref,
    DriverDailyFeeTier tier,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove tier?'),
        content: Text(
          'Drivers at ${tier.minDeliveries}+ deliveries today will fall '
          'back to whatever lower tier still applies (or owe nothing, if '
          'none does).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.danger),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(driverDailyFeeRepositoryProvider).deleteTier(tier.id);
    if (!context.mounted) return;
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'daily_fee_tier_removed',
      entityType: 'driver_daily_fee_tiers',
      summary: 'Removed the ${tier.minDeliveries}+ deliveries daily fee tier',
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tiersState = ref.watch(dailyFeeTiersProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Driver daily fee',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _openTierDialog(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add tier'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'A platform fee every driver must pay via Mobile Money before '
              "they can be given a new delivery - a hard block, enforced by "
              'the database, not just a warning. Priced by how many '
              "deliveries they've completed today: the highest tier below "
              "they've reached is what they owe, re-evaluated live as they "
              'complete more. No tiers = the whole feature is off. See '
              'Console > Daily Fees to review payments and confirm ones '
              'paid outside the app. Shown to drivers simply as '
              '"commission" - they never see how it\'s collected.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            AsyncValueView<List<DriverDailyFeeTier>>(
              value: tiersState,
              data: (tiers) {
                if (tiers.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No tiers set - the daily fee is off.',
                      style: TextStyle(color: Colors.grey.shade500),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final tier in tiers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${tier.minDeliveries}+ deliveries today  ·  '
                                '$currency ${tier.amount.toStringAsFixed(2)}',
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              onPressed: () => _openTierDialog(
                                context,
                                ref,
                                existing: tier,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: 18,
                                color: AppTheme.danger,
                              ),
                              onPressed: () => _deleteTier(context, ref, tier),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 110,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? preset.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _colorDot(preset.primary),
                const SizedBox(width: 6),
                _colorDot(preset.accent),
                const Spacer(),
                if (selected)
                  Icon(Icons.check_circle, size: 18, color: preset.primary),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              preset.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _colorDot(Color color) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
