import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivery_card.dart';
import '../providers/driver_providers.dart';

class DriverDashboardScreen extends ConsumerWidget {
  const DriverDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deliveries = ref.watch(myDeliveriesProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile != null ? 'Hi, ${profile.displayName}' : 'My deliveries'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authRepositoryProvider).signOut(),
          ),
        ],
      ),
      body: AsyncValueView<List<Delivery>>(
        value: deliveries,
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No deliveries assigned to you yet.',
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            );
          }

          final active = items
              .where((d) =>
                  d.status != DeliveryStatus.delivered && d.status != DeliveryStatus.cancelled)
              .toList();
          final finished = items
              .where((d) =>
                  d.status == DeliveryStatus.delivered || d.status == DeliveryStatus.cancelled)
              .toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myDeliveriesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader('Active (${active.length})'),
                  for (final delivery in active) ...[
                    DeliveryCard(
                      delivery: delivery,
                      onTap: () => context.push('/driver/delivery/${delivery.id}'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (finished.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionHeader('Completed'),
                  for (final delivery in finished) ...[
                    DeliveryCard(
                      delivery: delivery,
                      onTap: () => context.push('/driver/delivery/${delivery.id}'),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
          color: Colors.grey.shade600,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
