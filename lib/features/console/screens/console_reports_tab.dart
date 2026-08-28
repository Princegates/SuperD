import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commission_payment.dart';
import '../../../models/commission_status.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/driver_daily_fee.dart';
import '../../../models/payment.dart';
import '../../../models/payment_status.dart';
import '../../../shared/utils/csv_export.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/console_providers.dart';

/// Historical reporting with a date range, plus a CSV export of the
/// underlying records for whatever range is selected - a complement to
/// Overview (which is always all-time, no export) for pulling a specific
/// period's numbers or taking the raw data elsewhere.
class ConsoleReportsTab extends ConsumerStatefulWidget {
  const ConsoleReportsTab({super.key});

  @override
  ConsumerState<ConsoleReportsTab> createState() => _ConsoleReportsTabState();
}

class _ConsoleReportsTabState extends ConsumerState<ConsoleReportsTab> {
  DateTimeRange? _range;

  bool _inRange(DateTime dt) {
    final range = _range;
    if (range == null) return true;
    return !dt.isBefore(range.start) &&
        dt.isBefore(range.end.add(const Duration(days: 1)));
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  void _exportOrShowFallback(String filename, String csvContent) {
    final downloaded = downloadCsv(filename: filename, csvContent: csvContent);
    if (!downloaded && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV export is only available from the web dashboard.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveriesState = ref.watch(allDeliveriesProvider);
    final payments = ref.watch(allPaymentsProvider).valueOrNull ?? [];
    final commission =
        ref.watch(allCommissionPaymentsProvider).valueOrNull ?? [];
    final dailyFees = ref.watch(allDriverDailyFeesProvider).valueOrNull ?? [];
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final zones = ref.watch(zonesProvider).valueOrNull ?? [];

    final driverNames = {for (final d in drivers) d.id: d.displayName};
    final vendorNames = {for (final v in vendors) v.id: v.vendorName};
    final zoneNames = {for (final z in zones) z.id: z.name};

    return AsyncValueView<List<Delivery>>(
      value: deliveriesState,
      data: (allDeliveries) {
        final deliveries = allDeliveries
            .where((d) => _inRange(d.createdAt))
            .toList();
        final deliveryTrackingCodes = {
          for (final d in allDeliveries) d.id: d.trackingCode,
        };
        final filteredPayments = payments
            .where((p) => _inRange(p.createdAt))
            .toList();
        final filteredCommission = commission
            .where((c) => _inRange(c.createdAt))
            .toList();
        final filteredDailyFees = dailyFees
            .where((f) => _inRange(f.createdAt))
            .toList();

        final delivered = deliveries
            .where((d) => d.status == DeliveryStatus.delivered)
            .length;
        final cancelled = deliveries
            .where((d) => d.status == DeliveryStatus.cancelled)
            .length;
        final collected = filteredPayments
            .where((p) => p.status == PaymentStatus.paid)
            .fold(0.0, (s, p) => s + p.amount);
        final outstanding = filteredPayments
            .where((p) => p.status == PaymentStatus.pending)
            .fold(0.0, (s, p) => s + p.amount);
        final commissionCollected = filteredCommission
            .where((c) => c.status == CommissionStatus.paid)
            .fold(0.0, (s, c) => s + c.amount);
        final commissionOutstanding = filteredCommission
            .where((c) => c.status == CommissionStatus.due)
            .fold(0.0, (s, c) => s + c.amount);
        final dailyFeeCollected = filteredDailyFees
            .where((f) => f.status == DailyFeeStatus.paid)
            .fold(0.0, (s, f) => s + f.amount);
        final dailyFeePending = filteredDailyFees
            .where((f) => f.status == DailyFeeStatus.pending)
            .fold(0.0, (s, f) => s + f.amount);
        final currency = filteredPayments.isNotEmpty
            ? filteredPayments.first.currency
            : (filteredCommission.isNotEmpty
                  ? filteredCommission.first.currency
                  : 'GHS');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.date_range_outlined,
                      color: Colors.grey.shade600,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _range == null
                            ? 'All time'
                            : '${DateFormat('dd MMM yyyy').format(_range!.start)} '
                                  '– ${DateFormat('dd MMM yyyy').format(_range!.end)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (_range != null)
                      TextButton(
                        onPressed: () => setState(() => _range = null),
                        child: const Text('Clear'),
                      ),
                    OutlinedButton(
                      onPressed: _pickRange,
                      child: const Text('Choose range'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  label: 'Deliveries',
                  value: '${deliveries.length}',
                  color: AppTheme.primary,
                ),
                _StatTile(
                  label: 'Delivered',
                  value: '$delivered',
                  color: AppTheme.success,
                ),
                _StatTile(
                  label: 'Cancelled',
                  value: '$cancelled',
                  color: AppTheme.danger,
                ),
                _StatTile(
                  label: 'Collected',
                  value: '$currency ${collected.toStringAsFixed(2)}',
                  color: AppTheme.success,
                ),
                _StatTile(
                  label: 'Outstanding',
                  value: '$currency ${outstanding.toStringAsFixed(2)}',
                  color: AppTheme.warning,
                ),
                _StatTile(
                  label: 'Commission collected',
                  value: '$currency ${commissionCollected.toStringAsFixed(2)}',
                  color: AppTheme.success,
                ),
                _StatTile(
                  label: 'Commission outstanding',
                  value:
                      '$currency ${commissionOutstanding.toStringAsFixed(2)}',
                  color: AppTheme.warning,
                ),
                _StatTile(
                  label: 'Daily fees collected',
                  value: '$currency ${dailyFeeCollected.toStringAsFixed(2)}',
                  color: AppTheme.success,
                ),
                _StatTile(
                  label: 'Daily fees pending',
                  value: '$currency ${dailyFeePending.toStringAsFixed(2)}',
                  color: AppTheme.warning,
                ),
              ],
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Export raw records',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Downloads a CSV of exactly what\'s shown above (the '
                      'selected date range) - available from the web '
                      'dashboard.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Deliveries CSV'),
                          onPressed: () => _exportOrShowFallback(
                            'deliveries.csv',
                            buildCsv<Delivery>(
                              headers: const [
                                'Tracking code',
                                'Status',
                                'Customer',
                                'Phone',
                                'Pickup',
                                'Drop-off',
                                'Driver',
                                'Vendor',
                                'Zone',
                                'Created at',
                                'Delivered at',
                              ],
                              rows: deliveries,
                              toRow: (d) => [
                                d.trackingCode,
                                d.status.label,
                                d.customerName,
                                d.customerPhone,
                                d.pickupAddress,
                                d.dropoffAddress,
                                d.assignedDriverId == null
                                    ? null
                                    : driverNames[d.assignedDriverId],
                                d.vendorId == null
                                    ? null
                                    : vendorNames[d.vendorId],
                                d.zoneId == null ? null : zoneNames[d.zoneId],
                                d.createdAt.toIso8601String(),
                                d.deliveredAt?.toIso8601String(),
                              ],
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Payments CSV'),
                          onPressed: () => _exportOrShowFallback(
                            'payments.csv',
                            buildCsv<Payment>(
                              headers: const [
                                'Tracking code',
                                'Amount',
                                'Currency',
                                'Method',
                                'Status',
                                'Created at',
                                'Paid at',
                              ],
                              rows: filteredPayments,
                              toRow: (p) => [
                                deliveryTrackingCodes[p.deliveryId],
                                p.amount,
                                p.currency,
                                p.method.label,
                                p.status.label,
                                p.createdAt.toIso8601String(),
                                p.paidAt?.toIso8601String(),
                              ],
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Commission CSV'),
                          onPressed: () => _exportOrShowFallback(
                            'commission.csv',
                            buildCsv<CommissionPayment>(
                              headers: const [
                                'Driver',
                                'Tracking code',
                                'Amount',
                                'Currency',
                                'Status',
                                'Created at',
                                'Paid at',
                              ],
                              rows: filteredCommission,
                              toRow: (c) => [
                                driverNames[c.driverId] ?? 'Unknown driver',
                                c.deliveryId == null
                                    ? null
                                    : deliveryTrackingCodes[c.deliveryId],
                                c.amount,
                                c.currency,
                                c.status.label,
                                c.createdAt.toIso8601String(),
                                c.paidAt?.toIso8601String(),
                              ],
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text('Daily Fees CSV'),
                          onPressed: () => _exportOrShowFallback(
                            'daily_fees.csv',
                            buildCsv<DriverDailyFee>(
                              headers: const [
                                'Driver',
                                'Fee date',
                                'Amount',
                                'Currency',
                                'Status',
                                'Payment method',
                                'Created at',
                                'Paid at',
                              ],
                              rows: filteredDailyFees,
                              toRow: (f) => [
                                driverNames[f.driverId] ?? 'Unknown driver',
                                f.feeDate.toIso8601String().substring(0, 10),
                                f.amount,
                                f.currency,
                                f.status.label,
                                f.paymentMethod,
                                f.createdAt.toIso8601String(),
                                f.paidAt?.toIso8601String(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!kIsWeb) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Open the web dashboard to actually download - '
                        "export doesn't work from this build.",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
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

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

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
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
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
