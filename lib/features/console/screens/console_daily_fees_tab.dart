import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/delivery_status.dart';
import '../../../models/driver_daily_fee.dart';
import '../../../models/driver_daily_fee_tier.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/console_providers.dart';

/// The tiered daily Mobile Money platform fee every driver owes, priced by
/// how many deliveries they've completed today (tiers set from Console >
/// Settings) - real-time Paystack payments and manually-submitted
/// references both land here. Unlike Commission (owed per delivery), an
/// unpaid daily fee is a hard block: a driver can't be given a new
/// delivery at all until they pay up to their current tier or a
/// dispatcher waives that day for them (see `driver_daily_fee_paid()` in
/// `0037_tiered_daily_fee.sql`).
class ConsoleDailyFeesTab extends ConsumerWidget {
  const ConsoleDailyFeesTab({super.key});

  String get _today => DateTime.now().toIso8601String().substring(0, 10);

  Future<void> _confirmManual(
    WidgetRef ref,
    DriverDailyFee record,
    bool approve,
  ) async {
    await ref
        .read(driverDailyFeeRepositoryProvider)
        .confirmManualPayment(feeId: record.id, approve: approve);
    ref.invalidate(allDriverDailyFeesProvider);
  }

  Future<void> _waive(WidgetRef ref, String driverId) async {
    await ref.read(driverDailyFeeRepositoryProvider).waiveToday(driverId);
    ref.invalidate(allDriverDailyFeesProvider);
  }

  Future<void> _setTierOverride(
    WidgetRef ref,
    String driverId,
    String? tierId,
  ) async {
    await ref
        .read(profileRepositoryProvider)
        .setDailyFeeTierOverride(driverId, tierId);
    ref.invalidate(driversListProvider);
  }

  Future<void> _grantFreeDays(
    BuildContext context,
    WidgetRef ref,
    Profile driver,
  ) async {
    final controller = TextEditingController(text: '1');
    final days = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Grant free days to ${driver.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Number of free days'),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Unfocus before popping - works around a Flutter framework
              // bug where an autofocused TextField's FocusNode isn't
              // always cleanly detached before this dialog's element tree
              // is torn down, tripping the framework's own
              // "_dependents.isEmpty" assertion and crashing the app.
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(int.tryParse(controller.text.trim()));
            },
            child: const Text('Grant'),
          ),
        ],
      ),
    );
    if (days == null || days <= 0 || !context.mounted) return;

    await ref
        .read(driverDailyFeeRepositoryProvider)
        .grantFreeDays(driverId: driver.id, days: days);
    ref.invalidate(allFreeDayBalancesProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Granted $days free day${days == 1 ? '' : 's'} to '
            '${driver.displayName}',
          ),
        ),
      );
    }
  }

  /// Emergency escape hatch for a payment-gateway outage: lifts [driver]'s
  /// daily-fee/commission access block for a chosen duration without
  /// forgiving what they owe - see `payment_access_override_until` in
  /// `0068_driver_payment_access_override.sql`. Distinct from
  /// [_waive]/marking a commission row waived, which cancel the debt
  /// outright.
  Future<void> _grantAccess(
    BuildContext context,
    WidgetRef ref,
    Profile driver,
  ) async {
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

  Future<void> _revokeAccess(WidgetRef ref, Profile driver) async {
    await ref
        .read(profileRepositoryProvider)
        .setPaymentAccessOverride(driver.id, null);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'driver_payment_access_revoked',
      entityType: 'profiles',
      entityId: driver.id,
      summary:
          "Revoked ${driver.displayName}'s temporary payment-block "
          'access override',
    );
    ref.invalidate(driversListProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feesState = ref.watch(allDriverDailyFeesProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final tiers = ref.watch(dailyFeeTiersProvider).valueOrNull ?? [];
    final isSuperAdmin =
        ref.watch(currentProfileProvider).valueOrNull?.role ==
        UserRole.superAdmin;
    final freeDayThreshold = ref
        .watch(appSettingsProvider)
        .valueOrNull
        ?.freeDayDeliveryThreshold;
    final freeDayBalances =
        ref.watch(allFreeDayBalancesProvider).valueOrNull ?? {};
    final allDeliveries = ref.watch(allDeliveriesProvider).valueOrNull ?? [];
    final driverNames = {for (final d in drivers) d.id: d.displayName};

    final deliveredCounts = <String, int>{};
    final deliveredTodayCounts = <String, int>{};
    final today = _today;
    for (final d in allDeliveries) {
      if (d.status != DeliveryStatus.delivered || d.assignedDriverId == null) {
        continue;
      }
      deliveredCounts.update(
        d.assignedDriverId!,
        (c) => c + 1,
        ifAbsent: () => 1,
      );
      if (d.deliveredAt?.toLocal().toIso8601String().substring(0, 10) ==
          today) {
        deliveredTodayCounts.update(
          d.assignedDriverId!,
          (c) => c + 1,
          ifAbsent: () => 1,
        );
      }
    }

    // The highest tier a driver at [count] completed-today deliveries has
    // reached - mirrors driver_daily_fee_amount() in
    // 0037_tiered_daily_fee.sql. [tiers] is already sorted ascending by
    // minDeliveries (see dailyFeeTiersProvider).
    double owedFor(int count) {
      var owed = 0.0;
      for (final tier in tiers) {
        if (tier.minDeliveries > count) break;
        owed = tier.amount;
      }
      return owed;
    }

    return AsyncValueView<List<DriverDailyFee>>(
      value: feesState,
      data: (records) {
        // The daily fee itself (no tiers configured) being off doesn't mean
        // this whole tab has nothing to show - Emergency access below also
        // covers a driver blocked purely by overdue commission, which has
        // nothing to do with tiers. So this only skips the tier-dependent
        // sections (the "haven't paid today" list, tier overrides), not the
        // whole screen.
        final dailyFeeOff = tiers.isEmpty;

        final todaysByDriver = <String, List<DriverDailyFee>>{};
        for (final r in records.where((r) => _isToday(r, today))) {
          todaysByDriver.putIfAbsent(r.driverId, () => []).add(r);
        }
        final unpaidToday = dailyFeeOff
            ? <Profile>[]
            : drivers.where((d) {
                final owed = owedFor(deliveredTodayCounts[d.id] ?? 0);
                if (owed <= 0) return false;
                final todaysRecords = todaysByDriver[d.id] ?? const [];
                if (todaysRecords.any(
                  (r) => r.status == DailyFeeStatus.waived,
                )) {
                  return false;
                }
                final paid = todaysRecords
                    .where((r) => r.isCleared)
                    .fold(0.0, (sum, r) => sum + r.amount);
                return paid < owed;
              }).toList();

        final byCurrency = <String, List<DriverDailyFee>>{};
        for (final r in records) {
          byCurrency.putIfAbsent(r.currency, () => []).add(r);
        }

        final pendingManual = records
            .where(
              (r) =>
                  r.paymentMethod == 'manual' &&
                  r.status == DailyFeeStatus.pending,
            )
            .toList();

        final recent = records.take(30).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (dailyFeeOff) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'The driver daily fee is currently off. Add a tier in '
                    'Console > Settings to start collecting it. Commission '
                    'and Emergency access below are unaffected.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            for (final entry in byCurrency.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _CurrencySummary(
                  currency: entry.key,
                  records: entry.value,
                ),
              ),
            if (unpaidToday.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Haven't paid today (${unpaidToday.length})",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "These drivers can't be given a new delivery until "
                        'they pay or you waive today for them.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final driver in unpaidToday)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(child: Text(driver.displayName)),
                              TextButton(
                                onPressed: () => _waive(ref, driver.id),
                                child: const Text('Waive today'),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Emergency access',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "If the payment gateway is down and a driver can't "
                      'clear their block right now, grant them temporary '
                      "access here instead of waiving what they owe - it's "
                      'still due, just not blocking them meanwhile.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final driver in drivers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                driver.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (driver.hasActivePaymentAccessOverride) ...[
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  'Until ${DateFormat('d MMM, HH:mm').format(driver.paymentAccessOverrideUntil!)}',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _revokeAccess(ref, driver),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppTheme.danger,
                                ),
                                child: const Text('Revoke'),
                              ),
                            ] else
                              TextButton(
                                onPressed: () =>
                                    _grantAccess(context, ref, driver),
                                child: const Text('Grant access'),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (isSuperAdmin && tiers.isNotEmpty) ...[
              _TierOverridesCard(
                drivers: drivers,
                tiers: tiers,
                onChanged: (driverId, tierId) =>
                    _setTierOverride(ref, driverId, tierId),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Free day credits',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      freeDayThreshold == null
                          ? 'The automatic rule is off - set one in '
                                'Console > Settings, or grant free days by '
                                'hand below.'
                          : 'Automatically earned every $freeDayThreshold '
                                'completed deliveries. You can also grant '
                                'extra days by hand.',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final driver in drivers)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${driver.displayName} · '
                                '${deliveredCounts[driver.id] ?? 0} delivered',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if ((freeDayBalances[driver.id] ?? 0) > 0)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(
                                    alpha: 0.12,
                                  ),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '${freeDayBalances[driver.id]} banked',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.success,
                                  ),
                                ),
                              ),
                            TextButton(
                              onPressed: () =>
                                  _grantFreeDays(context, ref, driver),
                              child: const Text('Grant'),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (pendingManual.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Awaiting confirmation (${pendingManual.length})',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A driver submitted a Mobile Money reference for a '
                        'payment made outside the app - check it against '
                        'your MoMo statement before approving.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final record in pendingManual)
                        _ManualConfirmRow(
                          record: record,
                          driverName:
                              driverNames[record.driverId] ?? 'Unknown driver',
                          onApprove: () => _confirmManual(ref, record, true),
                          onReject: () => _confirmManual(ref, record, false),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recent payments',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (recent.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text(
                          'No daily fee payments recorded yet.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    for (final record in recent)
                      _FeeRow(
                        record: record,
                        driverName:
                            driverNames[record.driverId] ?? 'Unknown driver',
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

  bool _isToday(DriverDailyFee record, String today) =>
      record.feeDate.toIso8601String().substring(0, 10) == today;
}

class _CurrencySummary extends StatelessWidget {
  const _CurrencySummary({required this.currency, required this.records});

  final String currency;
  final List<DriverDailyFee> records;

  double _sum(DailyFeeStatus status) => records
      .where((r) => r.status == status)
      .fold(0.0, (sum, r) => sum + r.amount);

  @override
  Widget build(BuildContext context) {
    final pending = _sum(DailyFeeStatus.pending);
    final paid = _sum(DailyFeeStatus.paid);
    final waived = _sum(DailyFeeStatus.waived);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              currency,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _AmountTile(
                  label: 'Pending',
                  amount: pending,
                  currency: currency,
                  color: AppTheme.warning,
                ),
                _AmountTile(
                  label: 'Collected',
                  amount: paid,
                  currency: currency,
                  color: AppTheme.success,
                ),
                if (waived > 0)
                  _AmountTile(
                    label: 'Waived',
                    amount: waived,
                    currency: currency,
                    color: AppTheme.neutral,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountTile extends StatelessWidget {
  const _AmountTile({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
  });

  final String label;
  final double amount;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$currency ${amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _ManualConfirmRow extends StatelessWidget {
  const _ManualConfirmRow({
    required this.record,
    required this.driverName,
    required this.onApprove,
    required this.onReject,
  });

  final DriverDailyFee record;
  final String driverName;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$driverName · ${record.currency} '
              '${record.amount.toStringAsFixed(2)} · ref: '
              '${record.manualReference ?? '-'}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: onReject,
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Reject'),
          ),
          const SizedBox(width: 4),
          FilledButton(onPressed: onApprove, child: const Text('Approve')),
        ],
      ),
    );
  }
}

class _FeeRow extends StatelessWidget {
  const _FeeRow({required this.record, required this.driverName});

  final DriverDailyFee record;
  final String driverName;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$driverName · ${record.currency} '
              '${record.amount.toStringAsFixed(2)}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: record.status.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              record.status.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: record.status.color,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            DateFormat('dd MMM').format(record.feeDate),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}

/// Super-admin-only: pins a driver to one specific tier, overriding the
/// normal automatic tier-by-delivery-count calculation for them entirely -
/// see `daily_fee_tier_override_id` in `0038_daily_fee_tier_overrides.sql`.
/// Only shown once at least one tier is configured (nothing to pin to
/// otherwise).
class _TierOverridesCard extends StatelessWidget {
  const _TierOverridesCard({
    required this.drivers,
    required this.tiers,
    required this.onChanged,
  });

  final List<Profile> drivers;
  final List<DriverDailyFeeTier> tiers;
  final void Function(String driverId, String? tierId) onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tier overrides',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 4),
            Text(
              "Pin a driver to one tier regardless of how many deliveries "
              "they complete - overrides the automatic calculation for "
              'them entirely until set back to Automatic.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            for (final driver in drivers)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        driver.displayName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownButton<String?>(
                      value:
                          tiers.any(
                            (t) => t.id == driver.dailyFeeTierOverrideId,
                          )
                          ? driver.dailyFeeTierOverrideId
                          : null,
                      underline: const SizedBox.shrink(),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Automatic'),
                        ),
                        for (final tier in tiers)
                          DropdownMenuItem<String?>(
                            value: tier.id,
                            child: Text(
                              '${tier.minDeliveries}+ - '
                              '${tier.amount.toStringAsFixed(2)}',
                            ),
                          ),
                      ],
                      onChanged: (tierId) => onChanged(driver.id, tierId),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
