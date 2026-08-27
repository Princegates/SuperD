import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_settings.dart';
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
  String? _syncedFromSettings;
  bool _isSavingPricing = false;

  @override
  void dispose() {
    _baseFareController.dispose();
    _pricePerKmController.dispose();
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

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(appSettingsProvider);

    return AsyncValueView<AppSettings>(
      value: settingsState,
      data: (settings) {
        // Sync the text fields from the live settings row once per value
        // (not on every rebuild) so a super admin's in-progress edit isn't
        // clobbered by their own keystroke triggering a rebuild.
        final syncKey = '${settings.baseFare}|${settings.pricePerKm}';
        if (_syncedFromSettings != syncKey) {
          _syncedFromSettings = syncKey;
          _baseFareController.text = settings.baseFare.toStringAsFixed(2);
          _pricePerKmController.text = settings.pricePerKm.toStringAsFixed(2);
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
