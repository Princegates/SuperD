import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers/core_providers.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_status.dart';
import '../../../shared/widgets/account_menu_button.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../../shared/widgets/delivery_card.dart';
import '../../../shared/widgets/staggered_list_item.dart';
import '../providers/driver_providers.dart';

class DriverDashboardScreen extends ConsumerStatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  ConsumerState<DriverDashboardScreen> createState() =>
      _DriverDashboardScreenState();
}

class _DriverDashboardScreenState
    extends ConsumerState<DriverDashboardScreen> {
  Timer? _locationTimer;

  @override
  void initState() {
    super.initState();
    _startSharingLocation();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    super.dispose();
  }

  /// Shares this driver's position with dispatch every 15s for as long as
  /// this screen stays open and location is granted - no background
  /// tracking, nothing persists once the app is closed. A transient GPS or
  /// network failure is silently ignored; it just tries again next tick.
  Future<void> _startSharingLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      debugPrint(
        'SuperD: location services are off on this device - live '
        'location sharing needs them enabled.',
      );
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      debugPrint('SuperD: location permission not granted ($permission).');
      return;
    }
    _pushLocation();
    _locationTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _pushLocation(),
    );
  }

  Future<void> _pushLocation() async {
    final userId = ref.read(supabaseClientProvider).auth.currentUser?.id;
    if (userId == null) return;
    try {
      final position = await Geolocator.getCurrentPosition();
      await ref
          .read(profileRepositoryProvider)
          .updateLiveLocation(
            userId: userId,
            lat: position.latitude,
            lng: position.longitude,
          );
    } catch (e) {
      // Best-effort - skip this tick, try again on the next one. Logged
      // (not shown to the driver) so a persistent failure is visible in
      // `flutter run` output instead of silently never updating.
      debugPrint('SuperD: live location update failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final deliveries = ref.watch(myDeliveriesProvider);
    final profile = ref.watch(currentProfileProvider).valueOrNull;

    // A driver's own delivery list re-emits the full set on every change -
    // only ids that weren't there last time are a genuinely new assignment.
    // previous == null (still loading) is skipped so the very first load
    // doesn't fire one notification per existing delivery.
    ref.listen<AsyncValue<List<Delivery>>>(myDeliveriesProvider, (
      previous,
      next,
    ) {
      final priorIds = previous?.valueOrNull?.map((d) => d.id).toSet();
      final current = next.valueOrNull;
      if (priorIds == null || current == null) return;
      for (final delivery in current) {
        if (!priorIds.contains(delivery.id)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'New delivery assigned: #${delivery.trackingCode}',
              ),
              action: SnackBarAction(
                label: 'View',
                onPressed: () =>
                    context.push('/driver/delivery/${delivery.id}'),
              ),
            ),
          );
        }
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          profile != null ? 'Hi, ${profile.displayName}' : 'My deliveries',
        ),
        actions: const [
          AccountMenuButton(changePasswordRoute: '/driver/change-password'),
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
              .where(
                (d) =>
                    d.status != DeliveryStatus.delivered &&
                    d.status != DeliveryStatus.cancelled,
              )
              .toList();
          final finished = items
              .where(
                (d) =>
                    d.status == DeliveryStatus.delivered ||
                    d.status == DeliveryStatus.cancelled,
              )
              .toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myDeliveriesProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                if (active.isNotEmpty) ...[
                  _SectionHeader('Active (${active.length})'),
                  for (final (index, delivery) in active.indexed) ...[
                    StaggeredListItem(
                      index: index,
                      child: DeliveryCard(
                        delivery: delivery,
                        onTap: () =>
                            context.push('/driver/delivery/${delivery.id}'),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
                if (finished.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _SectionHeader('Completed'),
                  for (final (index, delivery) in finished.indexed) ...[
                    StaggeredListItem(
                      index: active.length + index,
                      child: DeliveryCard(
                        delivery: delivery,
                        onTap: () =>
                            context.push('/driver/delivery/${delivery.id}'),
                      ),
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
