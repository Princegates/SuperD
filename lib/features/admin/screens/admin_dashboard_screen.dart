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
  final _searchController = TextEditingController();
  String _query = '';

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
    _searchController.dispose();
    super.dispose();
  }

  /// How long a delivery may sit in a status before it is worth someone
  /// looking at it. Only the states where nothing happens without a
  /// person: a delivered or cancelled job is finished, and a scheduled
  /// one is already handled by ScheduledDeliveryBanner.
  static const _stuckAfter = {
    DeliveryStatus.pending: Duration(minutes: 20),
    DeliveryStatus.assigned: Duration(minutes: 45),
    DeliveryStatus.pickedUp: Duration(hours: 3),
    DeliveryStatus.inTransit: Duration(hours: 3),
  };

  /// Deliveries that have been sitting too long in a status that should
  /// have moved on. A scheduled delivery whose time has not come yet is
  /// not stuck - it is waiting on purpose.
  List<Delivery> _stuck(List<Delivery> all) {
    final now = DateTime.now();
    final overdue = <Delivery>[];
    for (final delivery in all) {
      final limit = _stuckAfter[delivery.status];
      if (limit == null) continue;
      if (delivery.scheduledAt case final at? when at.isAfter(now)) continue;
      // Measured from the last thing that actually happened to it, so a
      // job assigned two minutes ago is not judged on when it was raised.
      final since =
          delivery.pickedUpAt ?? delivery.assignedAt ?? delivery.createdAt;
      if (now.difference(since) > limit) overdue.add(delivery);
    }
    overdue.sort((a, b) {
      final aSince = a.pickedUpAt ?? a.assignedAt ?? a.createdAt;
      final bSince = b.pickedUpAt ?? b.assignedAt ?? b.createdAt;
      return aSince.compareTo(bSince);
    });
    return overdue;
  }

  /// The last nine digits of a Ghanaian number - the part that is the
  /// same however it was written.
  ///
  /// Numbers are stored internationally (+233 24 000 0002) but a
  /// dispatcher types what the customer said, which is almost always the
  /// local form (024 000 0002). Those differ in more than punctuation:
  /// the local leading 0 becomes 233, so a plain digits-contains match
  /// finds nothing. Trimming both to the subscriber number makes the two
  /// forms - and a partial number - all match.
  static String _significantDigits(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length > 9 ? digits.substring(digits.length - 9) : digits;
  }

  /// Matches the things a dispatcher has to hand when someone rings up:
  /// a tracking code read off a message, a name, an area, or a number.
  bool _matches(Delivery delivery, String query) {
    if (query.isEmpty) return true;
    final queryDigits = _significantDigits(query);
    final phone = _significantDigits(delivery.customerPhone);
    return delivery.trackingCode.toLowerCase().contains(query) ||
        delivery.customerName.toLowerCase().contains(query) ||
        delivery.dropoffAddress.toLowerCase().contains(query) ||
        (queryDigits.isNotEmpty &&
            phone.isNotEmpty &&
            phone.contains(queryDigits));
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
          if (deliveriesState.valueOrNull case final all?) ...[
            ScheduledDeliveryBanner(deliveries: all),
            if (_stuck(all) case final stuck when stuck.isNotEmpty)
              _StuckBanner(
                stuck: stuck,
                // Jumping to the oldest one is the action every time, so
                // the banner does it rather than describing it.
                onOpen: () =>
                    context.push('/admin/delivery/${stuck.first.id}'),
              ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _query = value.trim().toLowerCase()),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Search code, name, phone or address',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          _StatusFilterBar(
            value: _filter,
            onChanged: (status) => setState(() => _filter = status),
          ),
          Expanded(
            child: AsyncValueView<List<Delivery>>(
              value: deliveriesState,
              data: (all) {
                final items = all
                    .where((d) => _filter == null || d.status == _filter)
                    .where((d) => _matches(d, _query))
                    .toList();

                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: items.isEmpty
                      ? Center(
                          key: const ValueKey('empty'),
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _query.isNotEmpty
                                  ? 'Nothing matches "$_query"'
                                  : _filter != null
                                  ? 'No ${_filter!.label.toLowerCase()} deliveries'
                                  : 'No deliveries yet',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          key: ValueKey('$_filter|$_query'),
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

/// Deliveries that have stopped moving.
///
/// Distinct from [ScheduledDeliveryBanner], which is about work that has
/// not started yet on purpose - this is work that started and stalled: an
/// order nobody picked up, a rider who accepted and never collected, a
/// parcel collected hours ago and still not delivered. Without it these
/// surface when the customer rings, which is too late.
class _StuckBanner extends StatelessWidget {
  const _StuckBanner({required this.stuck, required this.onOpen});

  final List<Delivery> stuck;
  final VoidCallback onOpen;

  static String _age(Delivery delivery) {
    final since =
        delivery.pickedUpAt ?? delivery.assignedAt ?? delivery.createdAt;
    final elapsed = DateTime.now().difference(since);
    if (elapsed.inHours >= 24) return '${elapsed.inDays}d';
    if (elapsed.inHours >= 1) return '${elapsed.inHours}h';
    return '${elapsed.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    final oldest = stuck.first;
    return Material(
      color: AppTheme.danger.withValues(alpha: 0.08),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                size: 20,
                color: AppTheme.danger,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      stuck.length == 1
                          ? '1 delivery needs attention'
                          : '${stuck.length} deliveries need attention',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppTheme.danger,
                      ),
                    ),
                    Text(
                      'Oldest: ${oldest.trackingCode} \u00b7 '
                      '${oldest.status.label.toLowerCase()} for ${_age(oldest)}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
