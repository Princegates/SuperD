import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/commission_payment.dart';
import '../../../models/commission_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/console_providers.dart';

/// Driver commission - a flat fee, a percentage of the delivery's payment,
/// or both (set from Console > Settings) - owed to the business per
/// completed delivery, automatically recorded the moment a delivery is
/// marked delivered. This is where a dispatcher or super admin marks one
/// paid once the driver actually settles it.
class ConsoleCommissionTab extends ConsumerWidget {
  const ConsoleCommissionTab({super.key});

  Future<void> _markPaid(
    WidgetRef ref,
    BuildContext context,
    CommissionPayment record,
  ) async {
    await ref
        .read(commissionRepositoryProvider)
        .updateStatus(commissionId: record.id, status: CommissionStatus.paid);
    ref.invalidate(allCommissionPaymentsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commissionState = ref.watch(allCommissionPaymentsProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final driverNames = {for (final d in drivers) d.id: d.displayName};

    return AsyncValueView<List<CommissionPayment>>(
      value: commissionState,
      data: (records) {
        if (records.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No commission recorded yet. Set a flat fee and/or '
                'percentage per delivery in Console > Settings to start '
                'tracking it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade500),
              ),
            ),
          );
        }

        final byCurrency = <String, List<CommissionPayment>>{};
        for (final r in records) {
          byCurrency.putIfAbsent(r.currency, () => []).add(r);
        }

        final byDriver = <String, List<CommissionPayment>>{};
        for (final r in records) {
          byDriver.putIfAbsent(r.driverId, () => []).add(r);
        }
        final dueByDriver =
            byDriver.entries
                .map(
                  (e) => MapEntry(
                    e.key,
                    e.value
                        .where((r) => r.status == CommissionStatus.due)
                        .fold(0.0, (sum, r) => sum + r.amount),
                  ),
                )
                .where((e) => e.value > 0)
                .toList()
              ..sort((a, b) => b.value.compareTo(a.value));

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
            if (dueByDriver.isNotEmpty) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Owed by driver',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final entry in dueByDriver)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  driverNames[entry.key] ?? 'Unknown driver',
                                ),
                              ),
                              Text(
                                entry.value.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.warning,
                                ),
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
                      'Recent commission',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final record in recent)
                      _CommissionRow(
                        record: record,
                        driverName:
                            driverNames[record.driverId] ?? 'Unknown driver',
                        onMarkPaid: record.status == CommissionStatus.due
                            ? () => _markPaid(ref, context, record)
                            : null,
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

class _CurrencySummary extends StatelessWidget {
  const _CurrencySummary({required this.currency, required this.records});

  final String currency;
  final List<CommissionPayment> records;

  double _sum(CommissionStatus status) => records
      .where((r) => r.status == status)
      .fold(0.0, (sum, r) => sum + r.amount);

  @override
  Widget build(BuildContext context) {
    final due = _sum(CommissionStatus.due);
    final paid = _sum(CommissionStatus.paid);
    final waived = _sum(CommissionStatus.waived);

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
                  label: 'Outstanding',
                  amount: due,
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

class _CommissionRow extends StatelessWidget {
  const _CommissionRow({
    required this.record,
    required this.driverName,
    required this.onMarkPaid,
  });

  final CommissionPayment record;
  final String driverName;
  final VoidCallback? onMarkPaid;

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
            DateFormat('dd MMM').format(record.createdAt.toLocal()),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          if (onMarkPaid != null) ...[
            const SizedBox(width: 8),
            TextButton(onPressed: onMarkPaid, child: const Text('Mark paid')),
          ],
        ],
      ),
    );
  }
}
