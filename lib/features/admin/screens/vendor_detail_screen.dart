import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/commission_payment.dart';
import '../../../models/commission_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/payment.dart';
import '../../../models/vendor.dart';
import '../../console/providers/console_providers.dart';
import '../providers/admin_providers.dart';

/// One vendor, as a commercial relationship rather than a row to edit.
///
/// The Vendors list can rename, deactivate, resend a link and delete -
/// everything except answer the questions you actually have about a
/// vendor: how much do they send, what do they earn us, are they still
/// active. That is what this is for.
///
/// Everything here is derived from data the admin already streams (all
/// deliveries, all commission), so opening this costs no extra query.
class VendorDetailScreen extends ConsumerWidget {
  const VendorDetailScreen({super.key, required this.vendor});

  final Vendor vendor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveries = (ref.watch(allDeliveriesProvider).valueOrNull ?? [])
        .where((d) => d.vendorId == vendor.id)
        .toList();
    final commission =
        ref.watch(allCommissionPaymentsProvider).valueOrNull ?? [];
    final payments = ref.watch(allPaymentsProvider).valueOrNull ?? [];
    final currency =
        ref.watch(appSettingsProvider).valueOrNull?.currency ?? 'GHS';

    final stats = _VendorStats.from(
      deliveries: deliveries,
      commission: commission,
      payments: payments,
    );

    return Scaffold(
      appBar: AppBar(title: Text(vendor.vendorName)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (deliveries.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'This vendor has not sent a delivery yet. If they '
                  'registered a while ago, their link may never have '
                  'reached them - resend it from the Vendors list.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _Tile(
                  label: 'Deliveries',
                  value: '${stats.total}',
                  color: AppTheme.primary,
                ),
                _Tile(
                  label: 'This month',
                  value: '${stats.thisMonth}',
                  color: AppTheme.accent,
                ),
                _Tile(
                  label: 'Commission earned',
                  value: '$currency ${stats.commission.toStringAsFixed(2)}',
                  color: AppTheme.success,
                ),
                _Tile(
                  label: 'Average fare',
                  value: stats.averageFare == null
                      ? '-'
                      : '$currency ${stats.averageFare!.toStringAsFixed(2)}',
                  color: AppTheme.neutral,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Activity',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _Line(
                      label: 'Last delivery',
                      value: stats.lastOrder == null
                          ? 'never'
                          : DateFormat('d MMM y, h:mm a')
                                .format(stats.lastOrder!),
                      // Silence for a fortnight from a vendor who used to
                      // send work is the signal worth acting on, and it
                      // arrives before they tell you anything.
                      warn: stats.quiet,
                    ),
                    _Line(label: 'Delivered', value: '${stats.delivered}'),
                    _Line(
                      label: 'Cancelled',
                      value: '${stats.cancelled}',
                      warn: stats.cancelled > stats.delivered,
                    ),
                    _Line(label: 'In flight now', value: '${stats.inFlight}'),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Details',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 10),
                  _Line(label: 'Phone', value: vendor.phone),
                  if (vendor.email case final email?)
                    _Line(label: 'Email', value: email),
                  _Line(
                    label: 'Zone',
                    value: vendor.zoneName ?? 'no zone set',
                    warn: vendor.zoneName == null,
                  ),
                  _Line(
                    label: 'Registered',
                    value: DateFormat('d MMM y').format(vendor.createdAt),
                  ),
                  _Line(
                    label: 'Status',
                    value: vendor.isActive ? 'Active' : 'Deactivated',
                    warn: !vendor.isActive,
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

class _VendorStats {
  _VendorStats();

  int total = 0;
  int thisMonth = 0;
  int delivered = 0;
  int cancelled = 0;
  int inFlight = 0;
  double commission = 0;
  double _fareTotal = 0;
  int _fareCount = 0;
  DateTime? lastOrder;

  double? get averageFare => _fareCount == 0 ? null : _fareTotal / _fareCount;

  /// No work for a fortnight, from a vendor who has sent some before.
  bool get quiet =>
      lastOrder != null &&
      DateTime.now().difference(lastOrder!) > const Duration(days: 14);

  static _VendorStats from({
    required List<Delivery> deliveries,
    required List<CommissionPayment> commission,
    required List<Payment> payments,
  }) {
    final stats = _VendorStats();
    final now = DateTime.now();
    final theirDeliveryIds = {for (final d in deliveries) d.id};

    for (final d in deliveries) {
      stats.total++;
      if (d.createdAt.year == now.year && d.createdAt.month == now.month) {
        stats.thisMonth++;
      }
      switch (d.status) {
        case DeliveryStatus.delivered:
          stats.delivered++;
        case DeliveryStatus.cancelled:
          stats.cancelled++;
        default:
          stats.inFlight++;
      }
      if (stats.lastOrder == null || d.createdAt.isAfter(stats.lastOrder!)) {
        stats.lastOrder = d.createdAt;
      }
    }

    // Commission rows know their delivery, not their vendor, so the
    // vendor's own delivery ids are what ties the two together. Waived
    // rows are excluded - nothing was earned from them.
    for (final c in commission) {
      if (c.status == CommissionStatus.waived) continue;
      if (c.deliveryId case final id? when theirDeliveryIds.contains(id)) {
        stats.commission += c.amount;
      }
    }

    // The fare is what the customer paid the rider, which lives in
    // payments. Averaging the commission rows instead would report about
    // a tenth of the real figure under a label saying "fare".
    for (final p in payments) {
      if (!theirDeliveryIds.contains(p.deliveryId)) continue;
      stats._fareTotal += p.amount;
      stats._fareCount++;
    }
    return stats;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value, required this.color});

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value, this.warn = false});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: warn ? AppTheme.warning : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
