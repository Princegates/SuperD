import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/app_settings.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';

/// Super-admin-only app-wide settings - currently just the currency
/// payments are recorded and displayed in everywhere else in the app
/// (delivery fees, the Finance tab, payment cards on delivery detail).
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
          ],
        );
      },
    );
  }
}
