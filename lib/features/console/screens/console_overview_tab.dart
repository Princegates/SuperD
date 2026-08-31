import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commission_payment.dart';
import '../../../models/commission_status.dart';
import '../../../models/daily_fee_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_incident.dart';
import '../../../models/delivery_status.dart';
import '../../../models/driver_daily_fee.dart';
import '../../../models/payment.dart';
import '../../../models/payment_status.dart';
import '../../../models/profile.dart';
import '../../../models/user_role.dart';
import '../../../models/vendor.dart';
import '../../../models/zone.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';
import '../providers/console_providers.dart';

/// Reporting & analytics: delivery volume and outcomes, who's doing the
/// work, and where - all computed client-side from data every dispatcher
/// already has read access to, so there's no new backend query surface.
/// Covers every major record type in the database - deliveries, payments,
/// commission, staff, vendors, and zones - not just deliveries.
class ConsoleOverviewTab extends ConsumerWidget {
  const ConsoleOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesState = ref.watch(allDeliveriesProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final zones = ref.watch(zonesProvider).valueOrNull ?? [];
    final allStaff = ref.watch(allProfilesProvider).valueOrNull ?? [];
    final payments = ref.watch(allPaymentsProvider).valueOrNull ?? [];
    final commission =
        ref.watch(allCommissionPaymentsProvider).valueOrNull ?? [];
    final dailyFees = ref.watch(allDriverDailyFeesProvider).valueOrNull ?? [];
    final incidents = ref.watch(deliveryIncidentsProvider).valueOrNull ?? [];

    return AsyncValueView<List<Delivery>>(
      value: deliveriesState,
      data: (deliveries) {
        final total = deliveries.length;
        final statusCounts = <DeliveryStatus, int>{};
        for (final d in deliveries) {
          statusCounts.update(d.status, (c) => c + 1, ifAbsent: () => 1);
        }
        final delivered = statusCounts[DeliveryStatus.delivered] ?? 0;
        final cancelled = statusCounts[DeliveryStatus.cancelled] ?? 0;
        final completionRate = total == 0 ? 0.0 : delivered / total;
        final cancellationRate = total == 0 ? 0.0 : cancelled / total;

        final driverNames = {for (final d in drivers) d.id: d.displayName};
        final vendorNames = {for (final v in vendors) v.id: v.vendorName};
        final zoneNames = {for (final z in zones) z.id: z.name};
        final trackingCodes = {
          for (final d in deliveries) d.id: d.trackingCode,
        };

        final deliveredByDriver = <String, int>{};
        final byZone = <String, int>{};
        final byVendor = <String, int>{};
        for (final d in deliveries) {
          if (d.status == DeliveryStatus.delivered &&
              d.assignedDriverId != null) {
            deliveredByDriver.update(
              d.assignedDriverId!,
              (c) => c + 1,
              ifAbsent: () => 1,
            );
          }
          if (d.zoneId != null) {
            byZone.update(d.zoneId!, (c) => c + 1, ifAbsent: () => 1);
          }
          if (d.vendorId != null) {
            byVendor.update(d.vendorId!, (c) => c + 1, ifAbsent: () => 1);
          }
        }

        List<MapEntry<String, int>> topEntries(
          Map<String, int> counts,
          Map<String, String> names,
        ) {
          final entries =
              counts.entries
                  .map((e) => MapEntry(names[e.key] ?? 'Unknown', e.value))
                  .toList()
                ..sort((a, b) => b.value.compareTo(a.value));
          return entries.take(5).toList();
        }

        final driverLeaderboard = topEntries(deliveredByDriver, driverNames);
        final zoneActivity = topEntries(byZone, zoneNames);
        final vendorVolume = topEntries(byVendor, vendorNames);

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  label: 'Total deliveries',
                  value: '$total',
                  color: AppTheme.primary,
                  icon: Icons.local_shipping_outlined,
                ),
                _StatTile(
                  label: 'Completed',
                  value: '$delivered',
                  color: AppTheme.success,
                  icon: Icons.check_circle_outline,
                ),
                _StatTile(
                  label: 'Cancelled',
                  value: '$cancelled',
                  color: AppTheme.danger,
                  icon: Icons.cancel_outlined,
                ),
                _StatTile(
                  label: 'Completion rate',
                  value: '${(completionRate * 100).toStringAsFixed(0)}%',
                  color: AppTheme.accent,
                  icon: Icons.trending_up,
                ),
                _StatTile(
                  label: 'Cancellation rate',
                  value: '${(cancellationRate * 100).toStringAsFixed(0)}%',
                  color: AppTheme.neutral,
                  icon: Icons.trending_down,
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionCard(
              title: 'By status',
              icon: Icons.dashboard_outlined,
              iconColor: AppTheme.neutral,
              child: Column(
                children: [
                  for (final status in DeliveryStatus.values)
                    _RankedRow(
                      label: status.label,
                      count: statusCounts[status] ?? 0,
                      max: total,
                      color: status.color,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Top drivers (completed deliveries)',
              icon: Icons.person_outline,
              iconColor: AppTheme.primary,
              child: driverLeaderboard.isEmpty
                  ? const _EmptyRow('No completed deliveries yet')
                  : Column(
                      children: [
                        for (final (index, entry) in driverLeaderboard.indexed)
                          _RankedRow(
                            rank: index + 1,
                            label: entry.key,
                            count: entry.value,
                            max: driverLeaderboard.first.value,
                            color: AppTheme.primary,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Zone activity',
              icon: Icons.map_outlined,
              iconColor: AppTheme.accent,
              child: zoneActivity.isEmpty
                  ? const _EmptyRow('No zoned deliveries yet')
                  : Column(
                      children: [
                        for (final (index, entry) in zoneActivity.indexed)
                          _RankedRow(
                            rank: index + 1,
                            label: entry.key,
                            count: entry.value,
                            max: zoneActivity.first.value,
                            color: AppTheme.accent,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _SectionCard(
              title: 'Top vendors by volume',
              icon: Icons.storefront_outlined,
              iconColor: AppTheme.success,
              child: vendorVolume.isEmpty
                  ? const _EmptyRow('No vendor-submitted deliveries yet')
                  : Column(
                      children: [
                        for (final (index, entry) in vendorVolume.indexed)
                          _RankedRow(
                            rank: index + 1,
                            label: entry.key,
                            count: entry.value,
                            max: vendorVolume.first.value,
                            color: AppTheme.success,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            _FinanceSummaryCard(payments: payments),
            const SizedBox(height: 16),
            _CommissionSummaryCard(commission: commission),
            const SizedBox(height: 16),
            _DailyFeeSummaryCard(dailyFees: dailyFees),
            const SizedBox(height: 16),
            _StaffSummaryCard(staff: allStaff),
            const SizedBox(height: 16),
            _VendorSummaryCard(vendors: vendors),
            const SizedBox(height: 16),
            _ZonePricingSummaryCard(zones: zones),
            if (incidents.isNotEmpty) ...[
              const SizedBox(height: 16),
              _SectionCard(
                title: 'Rejections & cancellations',
                icon: Icons.report_problem_outlined,
                iconColor: AppTheme.danger,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final incident in incidents)
                      _IncidentRow(
                        incident: incident,
                        trackingCode: trackingCodes[incident.deliveryId] ?? '?',
                      ),
                  ],
                ),
              ),
            ],
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
    required this.icon,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
    this.icon,
    this.iconColor,
  });

  final String title;
  final Widget child;
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final color = iconColor ?? AppTheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.label,
    required this.count,
    required this.max,
    required this.color,
    this.rank,
  });

  final String label;
  final int count;
  final int max;
  final Color color;

  /// 1-based position in a leaderboard-style list (top drivers/zones/
  /// vendors) - shown as a small numbered badge. Omitted for a fixed-order
  /// list like "By status", which isn't ranked by count.
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : count / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          if (rank != null) ...[
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Text(
                '$rank',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          SizedBox(
            width: rank != null ? 104 : 130,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 9,
                backgroundColor: const Color(0xFFF0F1F4),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 28,
            child: Text(
              '$count',
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyRow extends StatelessWidget {
  const _EmptyRow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(color: Colors.grey.shade500));
  }
}

/// "Collected X · Outstanding Y" (or "· Pending Y"), with each amount
/// colored so the split reads at a glance - green for money already in,
/// amber for what's still owed - shared by the Finance/Commission/Daily
/// fee summary cards below.
class _MoneySplitLine extends StatelessWidget {
  const _MoneySplitLine({
    required this.collected,
    required this.outstanding,
    this.outstandingLabel = 'Outstanding',
  });

  final double collected;
  final double outstanding;
  final String outstandingLabel;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        style: TextStyle(color: Colors.grey.shade600, fontSize: 13.5),
        children: [
          const TextSpan(text: 'Collected '),
          TextSpan(
            text: collected.toStringAsFixed(2),
            style: const TextStyle(
              color: AppTheme.success,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: ' · $outstandingLabel '),
          TextSpan(
            text: outstanding.toStringAsFixed(2),
            style: const TextStyle(
              color: AppTheme.warning,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A quick collected-vs-outstanding total per currency - the full
/// breakdown (by method, recent payments) lives in the Finance tab; this
/// is just enough to see at a glance from Overview.
class _FinanceSummaryCard extends StatelessWidget {
  const _FinanceSummaryCard({required this.payments});

  final List<Payment> payments;

  @override
  Widget build(BuildContext context) {
    final byCurrency = <String, List<Payment>>{};
    for (final p in payments) {
      byCurrency.putIfAbsent(p.currency, () => []).add(p);
    }

    return _SectionCard(
      title: 'Finance',
      icon: Icons.payments_outlined,
      iconColor: AppTheme.primary,
      child: payments.isEmpty
          ? const _EmptyRow('No payments recorded yet')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in byCurrency.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: _MoneySplitLine(
                            collected: entry.value
                                .where((p) => p.status == PaymentStatus.paid)
                                .fold(0.0, (s, p) => s + p.amount),
                            outstanding: entry.value
                                .where(
                                  (p) => p.status == PaymentStatus.pending,
                                )
                                .fold(0.0, (s, p) => s + p.amount),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Same shape as [_FinanceSummaryCard], for the separate driver-commission
/// ledger - the full breakdown (per-driver, mark-as-paid) lives in the
/// Commission tab.
class _CommissionSummaryCard extends StatelessWidget {
  const _CommissionSummaryCard({required this.commission});

  final List<CommissionPayment> commission;

  @override
  Widget build(BuildContext context) {
    final byCurrency = <String, List<CommissionPayment>>{};
    for (final c in commission) {
      byCurrency.putIfAbsent(c.currency, () => []).add(c);
    }

    return _SectionCard(
      title: 'Commission',
      icon: Icons.request_quote_outlined,
      iconColor: AppTheme.accent,
      child: commission.isEmpty
          ? const _EmptyRow(
              'No commission recorded yet - set a flat fee per delivery '
              'in Console > Settings to start tracking it',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in byCurrency.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: _MoneySplitLine(
                            collected: entry.value
                                .where((c) => c.status == CommissionStatus.paid)
                                .fold(0.0, (s, c) => s + c.amount),
                            outstanding: entry.value
                                .where((c) => c.status == CommissionStatus.due)
                                .fold(0.0, (s, c) => s + c.amount),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _DailyFeeSummaryCard extends StatelessWidget {
  const _DailyFeeSummaryCard({required this.dailyFees});

  final List<DriverDailyFee> dailyFees;

  @override
  Widget build(BuildContext context) {
    final byCurrency = <String, List<DriverDailyFee>>{};
    for (final f in dailyFees) {
      byCurrency.putIfAbsent(f.currency, () => []).add(f);
    }

    return _SectionCard(
      title: 'Driver daily fees',
      icon: Icons.calendar_today_outlined,
      iconColor: AppTheme.neutral,
      child: dailyFees.isEmpty
          ? const _EmptyRow(
              'No daily fee payments recorded yet - add a tier in '
              'Console > Settings to start collecting it',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in byCurrency.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 50,
                          child: Text(
                            entry.key,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Expanded(
                          child: _MoneySplitLine(
                            collected: entry.value
                                .where((f) => f.status == DailyFeeStatus.paid)
                                .fold(0.0, (s, f) => s + f.amount),
                            outstanding: entry.value
                                .where(
                                  (f) => f.status == DailyFeeStatus.pending,
                                )
                                .fold(0.0, (s, f) => s + f.amount),
                            outstandingLabel: 'Pending',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// Headcount by role, plus how many drivers are pending approval, frozen,
/// or currently online - the full roster with names lives in Team.
class _StaffSummaryCard extends StatelessWidget {
  const _StaffSummaryCard({required this.staff});

  final List<Profile> staff;

  @override
  Widget build(BuildContext context) {
    final drivers = staff.where((p) => p.role == UserRole.driver).toList();
    final dispatchers = staff
        .where((p) => p.role == UserRole.dispatcher)
        .length;
    final superAdmins = staff
        .where((p) => p.role == UserRole.superAdmin)
        .length;
    final pendingDrivers = drivers.where((d) => !d.isActive).length;
    final frozenDrivers = drivers.where((d) => d.isFrozen).length;
    final onlineDrivers = drivers.where((d) => d.isOnline).length;

    return _SectionCard(
      title: 'Staff',
      icon: Icons.contacts_outlined,
      iconColor: AppTheme.primary,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniStat(
            label: 'Drivers',
            value: '${drivers.length}',
            icon: Icons.local_shipping_outlined,
          ),
          _MiniStat(
            label: 'Dispatchers',
            value: '$dispatchers',
            icon: Icons.badge_outlined,
          ),
          _MiniStat(
            label: 'Super admins',
            value: '$superAdmins',
            icon: Icons.verified_outlined,
          ),
          _MiniStat(
            label: 'Drivers online',
            value: '$onlineDrivers',
            color: AppTheme.success,
            icon: Icons.circle,
          ),
          if (pendingDrivers > 0)
            _MiniStat(
              label: 'Pending approval',
              value: '$pendingDrivers',
              color: AppTheme.warning,
              icon: Icons.hourglass_empty,
            ),
          if (frozenDrivers > 0)
            _MiniStat(
              label: 'Frozen',
              value: '$frozenDrivers',
              color: AppTheme.danger,
              icon: Icons.ac_unit,
            ),
        ],
      ),
    );
  }
}

/// Active vs inactive vendor links - the full roster (with the links
/// themselves) lives in Vendors.
class _VendorSummaryCard extends StatelessWidget {
  const _VendorSummaryCard({required this.vendors});

  final List<Vendor> vendors;

  @override
  Widget build(BuildContext context) {
    final active = vendors.where((v) => v.isActive).length;
    final inactive = vendors.length - active;

    return _SectionCard(
      title: 'Vendors',
      icon: Icons.storefront_outlined,
      iconColor: AppTheme.success,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniStat(
            label: 'Total',
            value: '${vendors.length}',
            icon: Icons.storefront_outlined,
          ),
          _MiniStat(
            label: 'Active links',
            value: '$active',
            color: AppTheme.success,
            icon: Icons.check_circle_outline,
          ),
          if (inactive > 0)
            _MiniStat(
              label: 'Deactivated',
              value: '$inactive',
              color: AppTheme.neutral,
              icon: Icons.cancel_outlined,
            ),
        ],
      ),
    );
  }
}

/// Which zones have their own pricing override vs use the app-wide
/// default - set from each zone's card in Console > Zones.
class _ZonePricingSummaryCard extends StatelessWidget {
  const _ZonePricingSummaryCard({required this.zones});

  final List<Zone> zones;

  @override
  Widget build(BuildContext context) {
    final customized = zones
        .where((z) => z.baseFare != null || z.pricePerKm != null)
        .toList();

    return _SectionCard(
      title: 'Zone pricing',
      icon: Icons.attach_money,
      iconColor: AppTheme.accent,
      child: zones.isEmpty
          ? const _EmptyRow('No zones yet')
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${customized.length} of ${zones.length} zone(s) override '
                  'the app-wide default rate',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                if (customized.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  for (final zone in customized)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text(zone.name)),
                          Text(
                            'base ${zone.baseFare?.toStringAsFixed(2) ?? '—'}'
                            ' · per km ${zone.pricePerKm?.toStringAsFixed(2) ?? '—'}',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    this.color,
    this.icon,
  });

  final String label;
  final String value;
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.primary;
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: c),
                const SizedBox(width: 5),
              ],
              Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: c,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// One driver-rejected or driver-cancelled delivery - [incident.note]
/// already reads as a full sentence naming the driver and what happened
/// (see `driver_reject_delivery()`/`driver_cancel_delivery()` in
/// `0036_driver_cancel_and_incident_reporting.sql`), so this just adds the
/// tracking code and when it happened.
class _IncidentRow extends StatelessWidget {
  const _IncidentRow({required this.incident, required this.trackingCode});

  final DeliveryIncident incident;
  final String trackingCode;

  @override
  Widget build(BuildContext context) {
    final isCancellation = incident.note.startsWith('Cancelled');
    final color = isCancellation ? AppTheme.danger : AppTheme.neutral;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isCancellation ? Icons.report_problem_outlined : Icons.block,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '#$trackingCode',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  incident.note,
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            DateFormat('d MMM, h:mm a').format(incident.createdAt.toLocal()),
            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
          ),
        ],
      ),
    );
  }
}
