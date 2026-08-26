import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivery_card.dart';
import '../../../shared/widgets/staggered_list_item.dart';
import '../providers/admin_providers.dart';

/// The "Deliveries" section of the admin dashboard shell
/// ([AdminShellScreen]) - just this section's own content, no app bar of
/// its own (the shell provides one, shared across every section).
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  DeliveryStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final deliveriesState = ref.watch(allDeliveriesProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final driverNames = {for (final d in drivers) d.id: d.displayName};
    final deliveries = deliveriesState.valueOrNull ?? [];

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/admin/new'),
        icon: const Icon(Icons.add),
        label: const Text('New delivery'),
      ),
      body: Column(
        children: [
          _QuickStatsRow(deliveries: deliveries, driverCount: drivers.length),
          _StatusFilterBar(
            value: _filter,
            onChanged: (status) => setState(() => _filter = status),
          ),
          Expanded(
            child: AsyncValueView<List<Delivery>>(
              value: deliveriesState,
              data: (all) {
                final items = _filter == null
                    ? all
                    : all.where((d) => d.status == _filter).toList();

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: items.isEmpty
                      ? Center(
                          key: const ValueKey('empty'),
                          child: Text(
                            'No deliveries yet',
                            style: TextStyle(color: Colors.grey.shade500),
                          ),
                        )
                      : RefreshIndicator(
                          key: ValueKey(_filter),
                          onRefresh: () async =>
                              ref.invalidate(allDeliveriesProvider),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                            itemCount: items.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final delivery = items[index];
                              final driverLabel =
                                  delivery.assignedDriverId == null
                                  ? 'Unassigned'
                                  : (driverNames[delivery.assignedDriverId] ??
                                        'Driver assigned');
                              return StaggeredListItem(
                                index: index,
                                child: DeliveryCard(
                                  delivery: delivery,
                                  subtitle:
                                      '${delivery.customerName} · $driverLabel',
                                  onTap: () => context.push(
                                    '/admin/delivery/${delivery.id}',
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A quick-glance row of KPI cards above the delivery list - the first
/// thing anyone (dispatcher or super admin) sees on this screen. Computed
/// client-side from the same delivery stream the list below already
/// watches, so there's no extra query.
class _QuickStatsRow extends StatelessWidget {
  const _QuickStatsRow({required this.deliveries, required this.driverCount});

  final List<Delivery> deliveries;
  final int driverCount;

  bool _isToday(DateTime dateTime) {
    final now = DateTime.now();
    final local = dateTime.toLocal();
    return local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
  }

  @override
  Widget build(BuildContext context) {
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

    return SizedBox(
      height: 96,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        children: [
          _StatCard(
            label: "Today's deliveries",
            value: '$today',
            color: AppTheme.primary,
          ),
          _StatCard(
            label: 'Pending',
            value: '$pending',
            color: AppTheme.warning,
          ),
          _StatCard(
            label: 'In progress',
            value: '$inProgress',
            color: AppTheme.accent,
          ),
          _StatCard(
            label: 'Delivered today',
            value: '$deliveredToday',
            color: AppTheme.success,
          ),
          _StatCard(
            label: 'Active drivers',
            value: '$activeDrivers/$driverCount',
            color: AppTheme.neutral,
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
      width: 136,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7EAEE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 2,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

class _StatusFilterBar extends StatelessWidget {
  const _StatusFilterBar({required this.value, required this.onChanged});

  final DeliveryStatus? value;
  final ValueChanged<DeliveryStatus?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          _chip(
            context,
            label: 'All',
            selected: value == null,
            onTap: () => onChanged(null),
          ),
          for (final status in DeliveryStatus.values)
            _chip(
              context,
              label: status.label,
              selected: value == status,
              onTap: () => onChanged(status),
            ),
        ],
      ),
    );
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppTheme.primaryLight,
        labelStyle: TextStyle(
          color: selected ? AppTheme.primary : Colors.black87,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
        side: BorderSide(
          color: selected ? AppTheme.primary : const Color(0xFFE0E4E9),
        ),
      ),
    );
  }
}
