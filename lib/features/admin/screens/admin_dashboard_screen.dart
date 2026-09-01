import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../models/staff_permission.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivery_card.dart';
import '../../../shared/widgets/staggered_list_item.dart';
import '../providers/admin_providers.dart';
import '../widgets/scheduled_delivery_banner.dart';

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

  // The "due soon"/"overdue" check in ScheduledDeliveryBanner and each
  // DeliveryCard depends on DateTime.now(), not on any data change - a
  // scheduled delivery becomes urgent purely because time passed, with no
  // row ever being written. Nothing else triggers a rebuild for that, so
  // this ticks one on its own every 30s while this screen is visible.
  late final Timer _reminderTicker = Timer.periodic(
    const Duration(seconds: 30),
    (_) => setState(() {}),
  );

  @override
  void dispose() {
    _reminderTicker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canCreateDeliveries =
        ref.watch(currentProfileProvider).valueOrNull?.hasPermission(
              StaffPermission.createDeliveries,
            ) ??
        false;
    final deliveriesState = ref.watch(allDeliveriesProvider);
    final drivers = ref.watch(driversListProvider).valueOrNull ?? [];
    final driverNames = {for (final d in drivers) d.id: d.displayName};

    // A live toast the moment the system (not a dispatcher) auto-assigns a
    // driver - either a new order's same-zone match or a mid-trip
    // auto-hand-off, see Delivery.autoAssigned. Compares each emission's
    // autoAssigned flags against the previous one so this only fires on
    // the actual transition into "auto-assigned", not on every unrelated
    // update to a delivery that already was. previous == null (first
    // load) is skipped, same reasoning as the driver dashboard's own
    // "new delivery assigned" snackbar - otherwise every already
    // auto-assigned delivery would toast the moment this screen opens.
    ref.listen<AsyncValue<List<Delivery>>>(allDeliveriesProvider, (
      previous,
      next,
    ) {
      final priorAutoAssigned = {
        for (final d in previous?.valueOrNull ?? const <Delivery>[])
          d.id: d.autoAssigned,
      };
      final current = next.valueOrNull;
      if (previous?.valueOrNull == null || current == null) return;
      final names = {
        for (final d in ref.read(driversListProvider).valueOrNull ?? const [])
          d.id: d.displayName,
      };
      for (final delivery in current) {
        final wasAutoAssigned = priorAutoAssigned[delivery.id] ?? false;
        if (delivery.autoAssigned && !wasAutoAssigned) {
          final driverName = delivery.assignedDriverId == null
              ? 'a driver'
              : (names[delivery.assignedDriverId] ?? 'a driver');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'System auto-assigned #${delivery.trackingCode} to $driverName',
              ),
              action: SnackBarAction(
                label: 'View',
                onPressed: () => context.push('/admin/delivery/${delivery.id}'),
              ),
            ),
          );
        }
      }
    });

    return Scaffold(
      floatingActionButton: canCreateDeliveries
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/admin/new'),
              icon: const Icon(Icons.add),
              label: const Text('New delivery'),
            )
          : null,
      body: Column(
        children: [
          if (deliveriesState.valueOrNull case final all?)
            ScheduledDeliveryBanner(deliveries: all),
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
