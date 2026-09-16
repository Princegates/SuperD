import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers/core_providers.dart';
import '../../features/admin/providers/admin_providers.dart';
import '../../models/profile.dart';
import 'audit_log.dart';

/// Shows the "grant temporary access" dialog for [driver] and, on
/// confirmation, lifts their daily-fee/commission block for the chosen
/// duration - see `payment_access_override_until` in
/// `0068_driver_payment_access_override.sql`. What they owe is unchanged;
/// this only lifts the assignment block for a while.
///
/// Shared between the Daily Fees tab (where a dispatcher browses every
/// blocked driver) and the delivery detail screen (a quick shortcut for
/// the one driver in front of them right now), so both stay in sync
/// instead of drifting apart as separate copies.
Future<void> grantPaymentAccessOverride({
  required BuildContext context,
  required WidgetRef ref,
  required Profile driver,
}) async {
  final now = DateTime.now();
  final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
  final until = await showDialog<DateTime>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Grant ${driver.displayName} temporary access'),
      content: const Text(
        "Lets them be given new deliveries even though today's daily fee "
        "or overdue commission isn't paid - for when the payment gateway "
        "is down and they can't clear it right now. What they owe is "
        'unchanged and still needs settling afterward, in-app once the '
        "gateway's back, a manual reference, or in person.",
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(now.add(const Duration(hours: 1))),
          child: const Text('1 hour'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(endOfToday),
          child: const Text('Rest of today'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(now.add(const Duration(hours: 24))),
          child: const Text('24 hours'),
        ),
      ],
    ),
  );
  if (until == null || !context.mounted) return;

  await ref
      .read(profileRepositoryProvider)
      .setPaymentAccessOverride(driver.id, until);
  await logAuditEvent(
    ref.read(supabaseClientProvider),
    action: 'driver_payment_access_granted',
    entityType: 'profiles',
    entityId: driver.id,
    summary:
        'Granted ${driver.displayName} temporary access past the daily-fee/'
        'commission block, until ${DateFormat('d MMM, HH:mm').format(until)} '
        '(payment-gateway outage override)',
  );
  ref.invalidate(driversListProvider);
  ref.invalidate(unpaidDriverIdsTodayProvider);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${driver.displayName} can be assigned deliveries until '
          '${DateFormat('d MMM, HH:mm').format(until)} regardless of what '
          "they owe - it's still due.",
        ),
      ),
    );
  }
}
