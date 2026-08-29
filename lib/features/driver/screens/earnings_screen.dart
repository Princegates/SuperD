import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/payment.dart';
import '../../../models/payment_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/driver_providers.dart';

/// A driver's own revenue history (today/this week/this month/this year -
/// summed from [Payment]s on their own deliveries, see
/// [PaymentRepository.watchMyPayments]) and commission payment history
/// (both the per-delivery flat fee and the tiered daily fee - see
/// [CommissionRepository.fetchForDriver]/
/// [DriverDailyFeeRepository.fetchHistoryForDriver]). The live "today's
/// revenue" figure itself is also shown compactly on the dashboard - see
/// `_RevenueStrip` in driver_dashboard_screen.dart, which opens this
/// screen when tapped.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final paymentsState = ref.watch(myPaymentsProvider);
    final currency =
        ref.watch(appSettingsProvider).valueOrNull?.currency ?? 'GHS';

    return Scaffold(
      appBar: AppBar(title: const Text('My earnings')),
      body: AsyncValueView<List<Payment>>(
        value: paymentsState,
        data: (payments) {
          final paid = payments.where((p) => p.status == PaymentStatus.paid);
          final now = DateTime.now();
          final startOfWeek = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));

          double sumWhere(bool Function(DateTime when) inRange) {
            return paid
                .where((p) => inRange((p.paidAt ?? p.createdAt).toLocal()))
                .fold(0.0, (sum, p) => sum + p.amount);
          }

          final today = sumWhere(
            (w) =>
                w.year == now.year && w.month == now.month && w.day == now.day,
          );
          final thisWeek = sumWhere((w) => !w.isBefore(startOfWeek));
          final thisMonth = sumWhere(
            (w) => w.year == now.year && w.month == now.month,
          );
          final thisYear = sumWhere((w) => w.year == now.year);

          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myCommissionHistoryProvider);
              ref.invalidate(myDailyFeeHistoryProvider);
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Revenue',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  'Collected from customers for deliveries you completed.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _RevenueTile(
                      label: 'Today',
                      amount: today,
                      currency: currency,
                    ),
                    _RevenueTile(
                      label: 'This week',
                      amount: thisWeek,
                      currency: currency,
                    ),
                    _RevenueTile(
                      label: 'This month',
                      amount: thisMonth,
                      currency: currency,
                    ),
                    _RevenueTile(
                      label: 'This year',
                      amount: thisYear,
                      currency: currency,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Commission payments',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  "What you've paid the platform - the per-delivery fee "
                  'and/or the daily fee, whichever apply.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                const _CommissionHistory(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RevenueTile extends StatelessWidget {
  const _RevenueTile({
    required this.label,
    required this.amount,
    required this.currency,
  });

  final String label;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7EAEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$currency ${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ).copyWith(color: AppTheme.primary),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

/// Merges both commission mechanisms into one chronological list - a
/// driver doesn't need to know or care which table a row came from, just
/// what they paid and when.
class _CommissionHistory extends ConsumerWidget {
  const _CommissionHistory();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commissionState = ref.watch(myCommissionHistoryProvider);
    final dailyFeeState = ref.watch(myDailyFeeHistoryProvider);

    if (commissionState.isLoading || dailyFeeState.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final commission = commissionState.valueOrNull ?? const [];
    final dailyFees = dailyFeeState.valueOrNull ?? const [];

    final rows =
        <
            (
              DateTime when,
              String label,
              double amount,
              String currency,
              Color color,
            )
          >[
            for (final c in commission)
              (
                c.createdAt,
                'Per-delivery commission - ${c.status.label}',
                c.amount,
                c.currency,
                c.status.color,
              ),
            for (final f in dailyFees)
              (
                f.createdAt,
                'Daily fee (${DateFormat('d MMM').format(f.feeDate)}) - ${f.status.label}',
                f.amount,
                f.currency,
                f.status.color,
              ),
          ]
          ..sort((a, b) => b.$1.compareTo(a.$1));

    if (rows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          'No commission charged yet.',
          style: TextStyle(color: Colors.grey.shade500),
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          for (final row in rows)
            ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 10, color: row.$5),
              title: Text(
                '${row.$4} ${row.$3.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(row.$2),
              trailing: Text(
                DateFormat('d MMM, h:mm a').format(row.$1.toLocal()),
                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }
}
