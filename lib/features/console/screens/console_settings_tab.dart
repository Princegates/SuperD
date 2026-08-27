import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/app_settings.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';

/// Super-admin-only app-wide settings: the currency payments are recorded
/// and displayed in everywhere else in the app (delivery fees, the
/// Finance tab, payment cards on delivery detail), and the UI theme.
class ConsoleSettingsTab extends ConsumerWidget {
  const ConsoleSettingsTab({super.key});

  Future<void> _changeCurrency(
    WidgetRef ref,
    String from,
    String to,
  ) async {
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(appSettingsProvider);

    return AsyncValueView<AppSettings>(
      value: settingsState,
      data: (settings) {
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
                          DropdownMenuItem(
                            value: c.code,
                            child: Text(c.label),
                          ),
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
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
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
