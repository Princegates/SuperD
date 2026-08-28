import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/driver_daily_fee.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/console_providers.dart';

/// The flat daily Mobile Money platform fee every driver owes (set from
/// Console > Settings) - real-time Hubtel payments and manually-submitted
/// references both land here. Unlike Commission (owed per delivery), an
/// unpaid daily fee is a hard block: a driver can't be given a new
/// delivery at all until they pay or a dispatcher waives that day for
/// them (see `driver_daily_fee_paid()` in `0031_driver_daily_fee.sql`).
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feesState = ref.watch(allDriverDailyFeesProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final dailyFeeSetting =
        ref.watch(appSettingsProvider).valueOrNull?.driverDailyFee ?? 0;
    final driverNames = {for (final d in drivers) d.id: d.displayName};

    return AsyncValueView<List<DriverDailyFee>>(
      value: feesState,
      data: (records) {
        if (dailyFeeSetting == 0) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'The driver daily fee is currently off. Set an amount in '
                'Console > Settings to start collecting it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        final today = _today;
        final todaysByDriver = {
          for (final r in records.where((r) => _isToday(r, today)))
            r.driverId: r,
        };
        final unpaidToday = drivers.where((d) {
          final today = todaysByDriver[d.id];
          return today == null || !today.isCleared;
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
