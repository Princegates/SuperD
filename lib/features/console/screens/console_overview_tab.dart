import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';

/// Reporting & analytics: delivery volume and outcomes, who's doing the
/// work, and where - all computed client-side from data every dispatcher
/// already has read access to, so there's no new backend query surface.
class ConsoleOverviewTab extends ConsumerWidget {
  const ConsoleOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesState = ref.watch(allDeliveriesProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final vendors = ref.watch(vendorsProvider).valueOrNull ?? [];
    final zones = ref.watch(zonesProvider).valueOrNull ?? [];

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
