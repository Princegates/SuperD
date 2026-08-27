import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../providers/admin_providers.dart';

/// One nav destination a [HomeScreen] can jump straight to, without either
/// screen knowing about the other's internals - the shell hands down just
/// enough (icon, label, a callback) to render a quick-action tile.
class DashboardQuickLink {
  const DashboardQuickLink(this.icon, this.label);

  final IconData icon;
  final String label;
}

/// The dashboard's landing page - shown before a dispatcher or super admin
/// picks a specific function to work in. Same underlying delivery stream
/// every other section already watches, just summarized instead of listed,
/// plus one-tap links into the sections this role can reach.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({
    super.key,
    required this.quickLinks,
    required this.onNavigate,
  });

  final List<DashboardQuickLink> quickLinks;
  final ValueChanged<String> onNavigate;

  bool _isToday(DateTime dateTime) {
    final now = DateTime.now();
    final local = dateTime.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesState = ref.watch(allDeliveriesProvider);
    // Only approved drivers count toward the roster here - one still
    // pending approval can't be assigned work yet (see
    // rankedDriversProvider), so they shouldn't inflate the denominator.
    final drivers = (ref.watch(driversListProvider).valueOrNull ?? [])
        .where((d) => d.isActive)
        .toList();
    final profile = ref.watch(currentProfileProvider).valueOrNull;

    return AsyncValueView<List<Delivery>>(
      value: deliveriesState,
      data: (deliveries) {
        final total = deliveries.length;
        final today = deliveries.where((d) => _isToday(d.createdAt)).length;
        final pending = deliveries
            .where((d) => d.status == DeliveryStatus.pending)
            .length;
        final inProgress = deliveries
            .where(
              (d) =>
                  d.status == DeliveryStatus.assigned ||
                  d.status == DeliveryStatus.pickedUp ||
                  d.status == DeliveryStatus.inTransit,
            )
            .length;
        final deliveredToday = deliveries
            .where(
              (d) =>
                  d.status == DeliveryStatus.delivered &&
                  d.deliveredAt != null &&
                  _isToday(d.deliveredAt!),
            )
            .length;
        final activeDrivers = deliveries
            .where(
              (d) =>
                  d.assignedDriverId != null &&
                  d.status != DeliveryStatus.delivered &&
                  d.status != DeliveryStatus.cancelled,
            )
            .map((d) => d.assignedDriverId)
            .toSet()
            .length;

        final statusCounts = <DeliveryStatus, int>{};
        for (final d in deliveries) {
          statusCounts.update(d.status, (c) => c + 1, ifAbsent: () => 1);
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _BrandHeader(name: profile?.displayName),
            const SizedBox(height: 24),
            Text(
              'Today at a glance',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  label: "Today's deliveries",
                  value: '$today',
                  color: AppTheme.primary,
                ),
                _StatTile(
                  label: 'Pending',
                  value: '$pending',
                  color: AppTheme.warning,
                ),
                _StatTile(
                  label: 'In progress',
                  value: '$inProgress',
                  color: AppTheme.accent,
                ),
                _StatTile(
                  label: 'Delivered today',
                  value: '$deliveredToday',
                  color: AppTheme.success,
                ),
                _StatTile(
                  label: 'Active drivers',
                  value: '$activeDrivers/${drivers.length}',
                  color: AppTheme.neutral,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'All deliveries by status',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                    if (total == 0)
                      Text(
                        'No deliveries yet',
                        style: TextStyle(color: Colors.grey.shade500),
                      )
                    else
                      for (final status in DeliveryStatus.values)
                        _StatusRow(
                          status: status,
                          count: statusCounts[status] ?? 0,
                          total: total,
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Go to',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 15,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final link in quickLinks)
                  _QuickLinkTile(
                    link: link,
                    onTap: () => onNavigate(link.label),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7EAEE)),
          ),
          child: Image.asset('assets/icon/icon.png'),
        ),
        const SizedBox(width: 14),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SuperD',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
            Text(
              name == null ? 'Delivery management' : 'Welcome back, $name',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
            ),
          ],
        ),
      ],
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.count,
    required this.total,
  });

  final DeliveryStatus status;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final fraction = total == 0 ? 0.0 : count / total;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(status.icon, size: 18, color: status.color),
          const SizedBox(width: 8),
          SizedBox(
            width: 100,
            child: Text(status.label, overflow: TextOverflow.ellipsis),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: const Color(0xFFF0F1F4),
                valueColor: AlwaysStoppedAnimation(status.color),
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

class _QuickLinkTile extends StatelessWidget {
  const _QuickLinkTile({required this.link, required this.onTap});

  final DashboardQuickLink link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 140,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7EAEE)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(link.icon, color: AppTheme.primary),
            const SizedBox(height: 10),
            Text(link.label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
