import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/core_providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/zone.dart';
import '../../../models/zone_location.dart';
import '../../../shared/screens/location_picker_screen.dart';
import '../../../shared/utils/audit_log.dart';
import '../../../shared/utils/reverse_geocode.dart';
import '../../../shared/widgets/async_value_view.dart';
import '../../admin/providers/admin_providers.dart';

/// Super-admin management of zones and the named places within each one.
/// Drivers/vendors only ever pick a zone by name from a dropdown elsewhere
/// in the app - this is where that dropdown's contents (and what each zone
/// actually covers) get defined.
class ConsoleZonesTab extends ConsumerWidget {
  const ConsoleZonesTab({super.key});

  Future<void> _addZone(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add zone'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Zone name'),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    await ref.read(vendorRepositoryProvider).createZone(name);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_created',
      entityType: 'zone',
      summary: 'Added zone $name',
    );
    ref.invalidate(zonesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zonesState = ref.watch(zonesProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addZone(context, ref),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Add zone'),
      ),
      body: AsyncValueView<List<Zone>>(
        value: zonesState,
        data: (zones) {
          if (zones.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No zones yet. Tap "Add zone" to create the first one.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            itemCount: zones.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) => _ZoneCard(zone: zones[index]),
          );
        },
      ),
    );
  }
}

class _ZoneCard extends ConsumerWidget {
  const _ZoneCard({required this.zone});

  final Zone zone;

  Future<void> _addLocation(BuildContext context, WidgetRef ref) async {
    final picked = await Navigator.of(context).push<LatLng>(
      MaterialPageRoute(
        builder: (context) =>
            LocationPickerScreen(title: 'Pin a location in ${zone.name}'),
      ),
    );
    if (picked == null || !context.mounted) return;

    final suggested = await reverseGeocode(picked.latitude, picked.longitude);
    if (!context.mounted) return;

    final controller = TextEditingController(text: suggested ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name this location'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Location name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    await ref
        .read(vendorRepositoryProvider)
        .addZoneLocation(
          zoneId: zone.id,
          name: name,
          lat: picked.latitude,
          lng: picked.longitude,
        );
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_location_added',
      entityType: 'zone',
      entityId: zone.id,
      summary: 'Added location $name to zone ${zone.name}',
    );
    ref.invalidate(zoneLocationsProvider(zone.id));
  }

  Future<void> _removeLocation(
    BuildContext context,
    WidgetRef ref,
    ZoneLocation location,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove location?'),
        content: Text('This removes "${location.name}" from ${zone.name}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppTheme.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(vendorRepositoryProvider).deleteZoneLocation(location.id);
    await logAuditEvent(
      ref.read(supabaseClientProvider),
      action: 'zone_location_removed',
      entityType: 'zone',
      entityId: zone.id,
      summary: 'Removed location ${location.name} from zone ${zone.name}',
    );
    ref.invalidate(zoneLocationsProvider(zone.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locationsState = ref.watch(zoneLocationsProvider(zone.id));

    return Card(
      child: ExpansionTile(
        title: Text(
          zone.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: locationsState.valueOrNull != null
            ? Text('${locationsState.valueOrNull!.length} location(s)')
            : null,
        children: [
          AsyncValueView<List<ZoneLocation>>(
            value: locationsState,
            loading: (_) => const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                height: 24,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            data: (locations) {
              return Column(
                children: [
                  for (final location in locations)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined, size: 20),
                      title: Text(location.name),
                      subtitle: location.hasCoordinates
                          ? Text(
                              '${location.lat!.toStringAsFixed(5)}, '
                              '${location.lng!.toStringAsFixed(5)}',
                            )
                          : null,
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                          color: AppTheme.danger,
                        ),
                        onPressed: () =>
                            _removeLocation(context, ref, location),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () => _addLocation(context, ref),
                        icon: const Icon(
                          Icons.add_location_alt_outlined,
                          size: 18,
                        ),
                        label: const Text('Add location'),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
