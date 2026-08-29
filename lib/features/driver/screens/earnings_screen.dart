import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/commission_status.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/delivery_status.dart';
import '../../../models/payment.dart';
import '../../../models/payment_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/driver_providers.dart';

/// A driver's own revenue history (today/a weekly or monthly bar chart -
/// summed from [Payment]s on their own deliveries, see
/// [PaymentRepository.watchMyPayments]) and commission payment history
/// (both the per-delivery flat fee and the tiered daily fee - see
/// [CommissionRepository.fetchForDriver]/
/// [DriverDailyFeeRepository.fetchHistoryForDriver]), as two separate
/// tabs. The live "today's revenue" figure itself is also shown compactly
/// on the dashboard - see `_RevenueStrip` in driver_dashboard_screen.dart,
/// which opens this screen when tapped.
class EarningsScreen extends StatelessWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My earnings'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Revenue'),
              Tab(text: 'Commission'),
            ],
          ),
        ),
        body: const TabBarView(children: [_RevenueTab(), _CommissionTab()]),
      ),
    );
  }
}

enum _ChartPeriod { weekly, monthly }

class _RevenueTab extends ConsumerStatefulWidget {
  const _RevenueTab();

  @override
  ConsumerState<_RevenueTab> createState() => _RevenueTabState();
}

class _RevenueTabState extends ConsumerState<_RevenueTab> {
  _ChartPeriod _period = _ChartPeriod.weekly;

  static const _weekdayLabels = ['M', 'TU', 'W', 'TH', 'F', 'SA', 'SU'];

  @override
  Widget build(BuildContext context) {
    final paymentsState = ref.watch(myPaymentsProvider);
    final currency =
        ref.watch(appSettingsProvider).valueOrNull?.currency ?? 'GHS';
    final commissionHistory =
        ref.watch(myCommissionHistoryProvider).valueOrNull ?? const [];
    final dailyFeeHistory =
        ref.watch(myDailyFeeHistoryProvider).valueOrNull ?? const [];
    final totalTrips = (ref.watch(myDeliveriesProvider).valueOrNull ?? const [])
        .where((d) => d.status == DeliveryStatus.delivered)
        .length;

    return AsyncValueView<List<Payment>>(
      value: paymentsState,
      data: (payments) {
        final paid = payments.where((p) => p.status == PaymentStatus.paid);
        final now = DateTime.now();

        double revenueOn(DateTime day) {
          return paid
              .where((p) {
                final when = (p.paidAt ?? p.createdAt).toLocal();
                return when.year == day.year &&
                    when.month == day.month &&
                    when.day == day.day;
              })
              .fold(0.0, (sum, p) => sum + p.amount);
        }

        double today = revenueOn(now);

        final List<(String label, double value)> bars;
        final bool Function(DateTime when) inPeriod;
        final String periodLabel;
        if (_period == _ChartPeriod.weekly) {
          final startOfWeek = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));
          bars = [
            for (var i = 0; i < 7; i++)
              (
                _weekdayLabels[i],
                revenueOn(startOfWeek.add(Duration(days: i))),
              ),
          ];
          final endOfWeek = startOfWeek.add(const Duration(days: 7));
          inPeriod = (w) => !w.isBefore(startOfWeek) && w.isBefore(endOfWeek);
          periodLabel = 'Weekly earnings';
        } else {
          final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
          final chunkCount = (daysInMonth / 7).ceil();
          bars = [
            for (var i = 0; i < chunkCount; i++)
              (
                'W${i + 1}',
                [
                  for (
                    var d = i * 7 + 1;
                    d <= daysInMonth && d <= (i + 1) * 7;
                    d++
                  )
                    revenueOn(DateTime(now.year, now.month, d)),
                ].fold(0.0, (sum, v) => sum + v),
              ),
          ];
          inPeriod = (w) => w.year == now.year && w.month == now.month;
          periodLabel = 'Monthly earnings';
        }

        final periodTotal = bars.fold(0.0, (sum, b) => sum + b.$2);

        final commissionPaid =
            commissionHistory
                .where(
                  (c) =>
                      c.status == CommissionStatus.paid &&
                      c.paidAt != null &&
                      inPeriod(c.paidAt!.toLocal()),
                )
                .fold(0.0, (sum, c) => sum + c.amount) +
            dailyFeeHistory
                .where(
                  (f) =>
                      f.status == DailyFeeStatus.paid &&
                      f.paidAt != null &&
                      inPeriod(f.paidAt!.toLocal()),
                )
                .fold(0.0, (sum, f) => sum + f.amount);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                _StatChip(
                  label: 'Today',
                  value: '$currency ${today.toStringAsFixed(2)}',
                ),
                const SizedBox(width: 12),
                _StatChip(label: 'Total trips', value: '$totalTrips'),
              ],
            ),
            const SizedBox(height: 18),
            _PeriodToggle(
              period: _period,
              onChanged: (p) => setState(() => _period = p),
            ),
            const SizedBox(height: 20),
            _BarChart(bars: bars),
            const SizedBox(height: 14),
            Center(
              child: Column(
                children: [
                  Text(
                    '$currency ${periodTotal.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ).copyWith(color: AppTheme.primary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    periodLabel,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periodLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _BreakdownRow(
                      label: 'Revenue',
                      amount: periodTotal,
                      currency: currency,
                    ),
                    const SizedBox(height: 8),
                    _BreakdownRow(
                      label: 'Commission paid',
                      amount: commissionPaid,
                      currency: currency,
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

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7EAEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodToggle extends StatelessWidget {
  const _PeriodToggle({required this.period, required this.onChanged});

  final _ChartPeriod period;
  final ValueChanged<_ChartPeriod> onChanged;

  Widget _button(_ChartPeriod value, String label) {
    final selected = period == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.grey.shade700,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          _button(_ChartPeriod.weekly, 'Weekly'),
          _button(_ChartPeriod.monthly, 'Monthly'),
        ],
      ),
    );
  }
}

/// A hand-rolled bar chart - no charting package needed for a handful of
/// bars scaled to their own max value.
class _BarChart extends StatelessWidget {
  const _BarChart({required this.bars});

  final List<(String label, double value)> bars;

  @override
  Widget build(BuildContext context) {
    final maxValue = bars.fold<double>(0, (m, b) => b.$2 > m ? b.$2 : m);
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final bar in bars)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      height: maxValue > 0
                          ? (100 * (bar.$2 / maxValue)).clamp(4, 100)
                          : 4,
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      bar.$1,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.label,
    required this.amount,
    required this.currency,
  });

  final String label;
  final double amount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        Text(
          '$currency ${amount.toStringAsFixed(2)}',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
      ],
    );
  }
}

/// Merges both commission mechanisms into one chronological list - a
/// driver doesn't need to know or care which table a row came from, just
/// what they paid and when. Per-delivery commission and the tiered daily
/// fee are billed together in one payment once there's a balance (see
/// `driver_total_amount_due()` in
/// `0050_bundle_commission_with_daily_fee.sql`), but each keeps its own
/// row here so a driver can still see exactly what made up any payment.
class _CommissionTab extends ConsumerWidget {
  const _CommissionTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commissionState = ref.watch(myCommissionHistoryProvider);
    final dailyFeeState = ref.watch(myDailyFeeHistoryProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myCommissionHistoryProvider);
        ref.invalidate(myDailyFeeHistoryProvider);
      },
      child: Builder(
        builder: (context) {
          if (commissionState.isLoading || dailyFeeState.isLoading) {
            return const Center(child: CircularProgressIndicator());
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

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                "What you've paid the platform - the per-delivery fee and/or "
                'the daily fee, whichever apply. Both are collected together '
                'once there\'s a balance to pay.',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No commission charged yet.',
                    style: TextStyle(color: Colors.grey.shade500),
                  ),
                )
              else
                Card(
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
                            DateFormat('d MMM, h:mm a')
                                .format(row.$1.toLocal()),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
