import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/commission_payment.dart';
import '../../../models/commission_status.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
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
                ),
                _StatTile(
                  label: 'Completed',
                  value: '$delivered',
                  color: AppTheme.success,
                ),
                _StatTile(
                  label: 'Cancelled',
                  value: '$cancelled',
                  color: AppTheme.danger,
                ),
                _StatTile(
                  label: 'Completion rate',
                  value: '${(completionRate * 100).toStringAsFixed(0)}%',
                  color: AppTheme.accent,
                ),
                _StatTile(
                  label: 'Cancellation rate',
                  value: '${(cancellationRate * 100).toStringAsFixed(0)}%',
                  color: AppTheme.neutral,
                ),
              ],
            ),
            const SizedBox(height: 20),
            _SectionCard(
              title: 'By status',
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
              child: driverLeaderboard.isEmpty
                  ? const _EmptyRow('No completed deliveries yet')
                  : Column(
                      children: [
                        for (final entry in driverLeaderboard)
                          _RankedRow(
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
              child: zoneActivity.isEmpty
                  ? const _EmptyRow('No zoned deliveries yet')
                  : Column(
                      children: [
                        for (final entry in zoneActivity)
                          _RankedRow(
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
              child: vendorVolume.isEmpty
                  ? const _EmptyRow('No vendor-submitted deliveries yet')
                  : Column(
                      children: [
                        for (final entry in vendorVolume)
                          _RankedRow(
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
            _StaffSummaryCard(staff: allStaff),
            const SizedBox(height: 16),
            _VendorSummaryCard(vendors: vendors),
            const SizedBox(height: 16),
            _ZonePricingSummaryCard(zones: zones),
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
              fontSize: 26,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
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
  });

  final String label;
  final int count;
  final int max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final fraction = max == 0 ? 0.0 : count / max;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 130,
            child: Text(label, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
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
                          child: Text(
                            'Collected ${entry.value.where((p) => p.status == PaymentStatus.paid).fold(0.0, (s, p) => s + p.amount).toStringAsFixed(2)}'
                            ' · Outstanding ${entry.value.where((p) => p.status == PaymentStatus.pending).fold(0.0, (s, p) => s + p.amount).toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade600),
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
                          child: Text(
                            'Collected ${entry.value.where((c) => c.status == CommissionStatus.paid).fold(0.0, (s, c) => s + c.amount).toStringAsFixed(2)}'
                            ' · Outstanding ${entry.value.where((c) => c.status == CommissionStatus.due).fold(0.0, (s, c) => s + c.amount).toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.grey.shade600),
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
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniStat(label: 'Drivers', value: '${drivers.length}'),
          _MiniStat(label: 'Dispatchers', value: '$dispatchers'),
          _MiniStat(label: 'Super admins', value: '$superAdmins'),
          _MiniStat(
            label: 'Drivers online',
            value: '$onlineDrivers',
            color: AppTheme.success,
          ),
          if (pendingDrivers > 0)
            _MiniStat(
              label: 'Pending approval',
              value: '$pendingDrivers',
              color: AppTheme.warning,
            ),
          if (frozenDrivers > 0)
            _MiniStat(
              label: 'Frozen',
              value: '$frozenDrivers',
              color: AppTheme.danger,
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
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          _MiniStat(label: 'Total', value: '${vendors.length}'),
          _MiniStat(
            label: 'Active links',
            value: '$active',
            color: AppTheme.success,
          ),
          if (inactive > 0)
            _MiniStat(
              label: 'Deactivated',
              value: '$inactive',
              color: AppTheme.neutral,
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
  const _MiniStat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 130,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (color ?? AppTheme.primary).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: color ?? AppTheme.primary,
            ),
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
