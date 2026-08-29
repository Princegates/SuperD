import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivery_card.dart';
import '../providers/driver_providers.dart';

/// A driver's full ride history in one place, split by status - Upcoming
/// (anything still active), Completed, and Canceled - rather than the
/// single "Active + Completed" list on the dashboard. Reuses the same
/// live [myDeliveriesProvider]/[myPaymentsProvider] the dashboard and "My
/// earnings" already watch, just presented as three separate lists.
class MyRidesScreen extends StatelessWidget {
  const MyRidesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My rides'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Upcoming'),
              Tab(text: 'Completed'),
              Tab(text: 'Canceled'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RidesList(filter: _RidesFilter.upcoming),
            _RidesList(filter: _RidesFilter.completed),
            _RidesList(filter: _RidesFilter.canceled),
          ],
        ),
      ),
    );
  }
}

enum _RidesFilter { upcoming, completed, canceled }

class _RidesList extends ConsumerWidget {
  const _RidesList({required this.filter});

  final _RidesFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveriesState = ref.watch(myDeliveriesProvider);
    final payments = ref.watch(myPaymentsProvider).valueOrNull ?? const [];
    final currency =
        ref.watch(appSettingsProvider).valueOrNull?.currency ?? 'GHS';

    String? fareFor(Delivery delivery) {
      for (final payment in payments) {
        if (payment.deliveryId == delivery.id) {
          return '$currency ${payment.amount.toStringAsFixed(2)}';
        }
      }
      return null;
    }

    return AsyncValueView<List<Delivery>>(
      value: deliveriesState,
      data: (items) {
        final filtered = switch (filter) {
          _RidesFilter.upcoming =>
            items
                .where(
                  (d) =>
                      d.status != DeliveryStatus.delivered &&
                      d.status != DeliveryStatus.cancelled,
                )
                .toList()
              ..sort(
                (a, b) => (a.scheduledAt ?? a.createdAt).compareTo(
                  b.scheduledAt ?? b.createdAt,
                ),
              ),
          _RidesFilter.completed =>
            items.where((d) => d.status == DeliveryStatus.delivered).toList(),
          _RidesFilter.canceled =>
            items.where((d) => d.status == DeliveryStatus.cancelled).toList(),
        };

        if (filtered.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(switch (filter) {
                _RidesFilter.upcoming => 'No upcoming rides.',
                _RidesFilter.completed => 'No completed rides yet.',
                _RidesFilter.canceled => 'No canceled rides.',
              }, style: TextStyle(color: Colors.grey.shade500)),
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myDeliveriesProvider),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final delivery in filtered) ...[
                DeliveryCard(
                  delivery: delivery,
                  fareText: fareFor(delivery),
                  onTap: () => context.push('/driver/delivery/${delivery.id}'),
                ),
                const SizedBox(height: 10),
              ],
            ],
          ),
        );
      },
    );
  }
}
