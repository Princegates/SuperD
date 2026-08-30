import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/route_stop.dart';
import '../../../shared/utils/navigation_launcher.dart';
import '../providers/driver_providers.dart';

/// One sensible visiting order across every pickup/drop-off this driver
/// currently has outstanding, instead of working through the dashboard's
/// per-delivery list one at a time - see `optimizeDriverRoute()` for how
/// the order is worked out. Purely a planning aid: tapping a stop opens
/// that delivery's own detail screen (where accept/pickup/deliver still
/// happens exactly as before), and its "Navigate" button launches
/// turn-by-turn directions to that stop specifically.
class DriverRouteScreen extends ConsumerWidget {
  const DriverRouteScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stops = ref.watch(driverRouteProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My route')),
      body: stops.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  "Nothing to plan right now - a route shows up here once "
                  'you have an active delivery with a pickup or drop-off '
                  'point set.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade500),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: stops.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _RouteStopTile(
                index: index,
                stop: stops[index],
                onTap: () => context.push(
                  '/driver/delivery/${stops[index].delivery.id}',
                ),
              ),
            ),
    );
  }
}

class _RouteStopTile extends StatelessWidget {
  const _RouteStopTile({
    required this.index,
    required this.stop,
    required this.onTap,
  });

  final int index;
  final RouteStop stop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: AppTheme.primary.withValues(alpha: 0.1),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          stop.isPickup
                              ? Icons.trip_origin
                              : Icons.place_outlined,
                          size: 16,
                          color: stop.isPickup
                              ? AppTheme.warning
                              : AppTheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          stop.isPickup ? 'Pick up' : 'Drop off',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '#${stop.delivery.trackingCode}',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      stop.address,
                      style: TextStyle(color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Navigate',
                icon: const Icon(Icons.directions_outlined),
                onPressed: () => launchNavigation(lat: stop.lat, lng: stop.lng),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
